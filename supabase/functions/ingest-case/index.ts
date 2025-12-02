// Supabase Edge Function: Ingest Case
// Handles AT data ingestion from TiParser API

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const TIPARSER_BASE_URL = Deno.env.get('TIPARSER_URL') || 'https://tiparser-dev.onrender.com'
const TIPARSER_API_KEY = Deno.env.get('TIPARSER_API_KEY') || ''
const LOGIQS_USERNAME = Deno.env.get('LOGIQS_USERNAME') || ''
const LOGIQS_PASSWORD = Deno.env.get('LOGIQS_PASSWORD') || ''
const CASEHELPER_BASE_URL = Deno.env.get('CASEHELPER_API_URL') || 'https://casehelper-backend.onrender.com'
const CASEHELPER_USERNAME = Deno.env.get('CASEHELPER_USERNAME') || ''
const CASEHELPER_PASSWORD = Deno.env.get('CASEHELPER_PASSWORD') || ''
const CASEHELPER_API_KEY = Deno.env.get('CASEHELPER_API_KEY') || ''

interface TiParserFile {
  case_document_id?: string
  id?: string
  document_id?: string
  filename?: string
  owner?: string
}

interface ParsedATRecord {
  tax_year?: number | string
  filing_status?: string
  adjusted_gross_income?: number
  taxable_income?: number
  account_balance?: number
  accrued_interest?: number
  accrued_penalty?: number
  total_balance?: number
  tax_per_return?: number
  processing_date?: string
  transactions?: any[]
  source_file?: string
  owner?: string
  return_filed_date?: string
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // Get Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Parse request body
    const { caseNumber } = await req.json()

    if (!caseNumber) {
      return new Response(
        JSON.stringify({ error: 'Case number is required' }),
        {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      )
    }

    console.log(`🚀 Starting ingestion for case ${caseNumber}`)

    // Step 1: Get or create case
    let { data: caseData, error: caseError } = await supabase
      .from('cases')
      .select('id')
      .eq('case_number', caseNumber)
      .single()

    if (caseError && caseError.code === 'PGRST116') {
      // Case doesn't exist, create it
      const { data: newCase, error: createError } = await supabase
        .from('cases')
        .insert({ case_number: caseNumber })
        .select('id')
        .single()

      if (createError) {
        throw new Error(`Failed to create case: ${createError.message}`)
      }

      caseData = newCase
      console.log(`✅ Created new case: ${caseData.id}`)
    } else if (caseError) {
      throw new Error(`Failed to check case: ${caseError.message}`)
    }

    const caseId = caseData!.id

    // Step 2: Login to TiParser if needed
    const sessionCookies = await loginToTiParser()
    const headers = {
      'x-api-key': TIPARSER_API_KEY,
      'Cookie': sessionCookies,
    }

    // Track Bronze IDs and file counts
    let atBronzeId: string | null = null
    let bronzeWiId: string | null = null
    let totalPdfsStored = 0

    // Step 3: Download and store PDFs FIRST (this triggers the pipeline)
    console.log(`📋 Listing AT PDF files for case ${caseNumber}...`)
    const filesUrl = `${TIPARSER_BASE_URL}/transcripts/at/${caseNumber}`
    
    let filesResponse = await fetch(filesUrl, {
      headers,
      method: 'GET',
    })

    // If auth error, try logging in again
    if (filesResponse.status === 500) {
      const text = await filesResponse.text()
      if (text.includes('Authentication required')) {
        console.log('🔐 Authentication required, logging in...')
        const newCookies = await loginToTiParser()
        headers['Cookie'] = newCookies
        
        filesResponse = await fetch(filesUrl, {
          headers,
          method: 'GET',
        })
      }
    }

    let files: TiParserFile[] = []
    if (filesResponse.ok) {
      const filesData = await filesResponse.json()
      files = filesData.files || (Array.isArray(filesData) ? filesData : [])
      console.log(`✅ Found ${files.length} AT PDF files`)
    } else {
      const errorText = await filesResponse.text()
      console.warn(`⚠️ Failed to list PDF files: ${filesResponse.status} - ${errorText.substring(0, 200)}`)
    }

    // Step 4: Download and store PDFs with parse_status = 'pending' (triggers parsing pipeline)
    const storedPdfIds: string[] = []
    if (files.length > 0) {
      const BATCH_SIZE = 5
      for (let batchStart = 0; batchStart < files.length; batchStart += BATCH_SIZE) {
        const batch = files.slice(batchStart, batchStart + BATCH_SIZE)
        
        await Promise.all(batch.map(async (file, batchIndex) => {
          const i = batchStart + batchIndex
          const docId = file.case_document_id || file.id || file.document_id
          const filename = file.filename || `unknown_${docId}.pdf`
          const owner = file.owner || 'TP'

          try {
            // Download PDF
            const downloadUrl = `${TIPARSER_BASE_URL}/transcripts/download/at/${caseNumber}/${docId}`
            let pdfResponse = await fetch(downloadUrl, {
              headers,
              method: 'GET',
            })

            if (pdfResponse.status === 500) {
              const text = await pdfResponse.text()
              if (text.includes('Authentication required')) {
                const newCookies = await loginToTiParser()
                headers['Cookie'] = newCookies
                pdfResponse = await fetch(downloadUrl, { headers, method: 'GET' })
              }
            }

            if (!pdfResponse.ok) {
              console.error(`❌ Failed to download ${filename}: ${pdfResponse.status}`)
              return
            }

            const pdfBytes = await pdfResponse.arrayBuffer()
            const storagePath = `at-transcripts/${caseNumber}/${filename}`
            const pdfBlob = new Blob([pdfBytes], { type: 'application/pdf' })
            
            // Store in storage
            console.log(`📤 Uploading PDF to storage: ${storagePath}`)
            const { data: uploadData, error: uploadError } = await supabase.storage
              .from('case-pdfs')
              .upload(storagePath, pdfBlob, {
                contentType: 'application/pdf',
                upsert: true,
              })
            
            if (uploadError) {
              console.error(`❌ Storage upload failed for ${filename}:`, uploadError)
              throw new Error(`Failed to upload PDF to storage: ${uploadError.message}`)
            }
            
            console.log(`✅ PDF uploaded successfully: ${storagePath}`)

            // Insert into bronze_pdf_raw with parse_status = 'pending' (triggers parsing)
            // Use upsert to prevent duplicates based on case_id + file_name
            console.log(`📝 Upserting PDF into bronze_pdf_raw: ${filename}, case_id: ${caseNumber}`)
            const { data: pdfRecord, error: pdfInsertError } = await supabase
              .from('bronze_pdf_raw')
              .upsert({
                case_id: caseNumber, // TEXT type
                document_type: 'AT',
                file_name: filename,
                storage_path: storagePath,
                owner: owner,
                parse_status: 'pending', // ⭐ This should trigger parsing pipeline
                downloaded_at: new Date().toISOString(),
              }, {
                onConflict: 'case_id,file_name', // Prevent duplicates
                ignoreDuplicates: false // Update if exists
              })
              .select('pdf_id, case_id, file_name, parse_status')
              .single()

            if (pdfInsertError) {
              console.error(`❌ Failed to insert PDF into bronze_pdf_raw: ${pdfInsertError.message}`)
              console.error(`   Error details: ${JSON.stringify(pdfInsertError)}`)
              console.error(`   Case ID: ${caseNumber}, Filename: ${filename}`)
            } else if (pdfRecord) {
              // Use pdf_id (the actual column name in production)
              const pdfId = pdfRecord.pdf_id
              if (pdfId) {
                storedPdfIds.push(pdfId)
                totalPdfsStored++
                console.log(`✅ Stored PDF: ${filename} (ID: ${pdfId}, Status: ${pdfRecord.parse_status || 'pending'})`)
              } else {
                console.error(`❌ PDF record missing pdf_id field. Record keys: ${Object.keys(pdfRecord).join(', ')}`)
                console.error(`   Full record: ${JSON.stringify(pdfRecord)}`)
              }
            } else {
              console.warn(`⚠️ PDF insert returned no record and no error for: ${filename}`)
            }

            // Also insert into pdf_documents for viewer (with duplicate prevention)
            const extractedYear = extractYearFromFilename(filename)
            const { error: pdfDocError } = await supabase
              .from('pdf_documents')
              .upsert({
                case_id: caseId,
                document_type: 'AT',
                file_name: filename,
                file_path: storagePath,
                file_size: pdfBytes.byteLength,
                tax_year: extractedYear,
              }, {
                onConflict: 'case_id,file_name', // Prevent duplicates by case + filename
                ignoreDuplicates: false // Update if exists
              })
            
            if (pdfDocError) {
              console.warn(`⚠️ Failed to upsert PDF document: ${pdfDocError.message}`)
            }

          } catch (error) {
            console.error(`❌ Error processing PDF ${filename}:`, error)
          }
        }))
      }
    }

    // Step 5: Call TiParser Analysis API to parse the PDFs and get structured data
    console.log(`🔍 Calling TiParser AT analysis to parse PDFs for case ${caseNumber}...`)
    const atAnalysisUrl = `${TIPARSER_BASE_URL}/analysis/at/${caseNumber}`
    
    let atAnalysisResponse = await fetch(atAnalysisUrl, {
      headers,
      method: 'GET',
    })

    // If auth error, try logging in again
    if (atAnalysisResponse.status === 500 || atAnalysisResponse.status === 401) {
      const text = await atAnalysisResponse.text()
      if (text.includes('Authentication required') || text.includes('Unauthorized')) {
        console.log('🔐 Re-authenticating for AT analysis...')
        const newCookies = await loginToTiParser()
        headers['Cookie'] = newCookies
        
        atAnalysisResponse = await fetch(atAnalysisUrl, {
          headers,
          method: 'GET',
        })
      }
    }

    let atData: any = null
    if (atAnalysisResponse.ok) {
      atData = await atAnalysisResponse.json()
      console.log(`✅ Got parsed AT data from TiParser analysis`)
      
      // Step 6: Insert parsed data into Bronze (this triggers Silver → Gold)
      if (atData && (atData.records || atData.at_records || atData.data)) {
        console.log(`💾 Inserting parsed AT data into Bronze (triggers Silver → Gold)...`)
        
        const { data: bronzeResult, error: bronzeError } = await supabase
          .from('bronze_at_raw')
          .insert({
            case_id: caseNumber, // Use case_number, not UUID
            raw_response: atData, // Store the full parsed response
          })
          .select('bronze_id')
          .single()

        if (bronzeError) {
          console.error(`❌ Failed to insert AT data into Bronze: ${bronzeError.message}`)
        } else {
          atBronzeId = bronzeResult.bronze_id
          console.log(`✅ Inserted AT data into Bronze (ID: ${atBronzeId}) - Silver/Gold triggers should fire automatically`)
        }
      } else {
        console.warn(`⚠️ TiParser AT analysis returned empty or invalid data structure`)
      }
      
      // ⭐ Update PDFs to 'completed' if analysis API call succeeded (even if no data returned)
      // This prevents PDFs from being stuck in 'pending' forever
      if (storedPdfIds.length > 0) {
        console.log(`🔄 Attempting to update ${storedPdfIds.length} AT PDFs to 'completed' status...`)
        console.log(`   PDF IDs: ${storedPdfIds.join(', ')}`)
        
        const { data: updateData, error: updateError } = await supabase
          .from('bronze_pdf_raw')
          .update({ parse_status: 'completed' })
          .in('pdf_id', storedPdfIds)
          .select('pdf_id, parse_status')
        
        if (updateError) {
          console.error(`❌ Failed to update PDF status: ${updateError.message}`)
          console.error(`   Error details: ${JSON.stringify(updateError)}`)
        } else {
          console.log(`✅ Updated ${updateData?.length || 0} AT PDFs to 'completed' status`)
          if (updateData && updateData.length > 0) {
            console.log(`   Updated IDs: ${updateData.map((r: any) => r.pdf_id || r.bronze_pdf_id || r.id).join(', ')}`)
          }
        }
      } else {
        console.warn(`⚠️ No PDF IDs stored - cannot update PDF status. storedPdfIds is empty.`)
      }
    } else {
      const errorText = await atAnalysisResponse.text()
      console.warn(`⚠️ TiParser AT analysis failed: ${atAnalysisResponse.status} - ${errorText.substring(0, 200)}`)
      
      // ⚠️ If analysis fails, mark PDFs as 'failed' instead of leaving them 'pending'
      if (storedPdfIds.length > 0) {
        await supabase
          .from('bronze_pdf_raw')
          .update({ parse_status: 'failed' })
          .in('pdf_id', storedPdfIds)
        console.log(`⚠️ Marked ${storedPdfIds.length} AT PDFs as 'failed' due to analysis error`)
      }
    }

    // Step 7: Download and store WI PDFs
    console.log(`📋 Listing WI PDF files for case ${caseNumber}...`)
    const wiFilesUrl = `${TIPARSER_BASE_URL}/transcripts/wi/${caseNumber}`
    
    let wiFilesResponse = await fetch(wiFilesUrl, {
      headers,
      method: 'GET',
    })

    if (wiFilesResponse.status === 500) {
      const text = await wiFilesResponse.text()
      if (text.includes('Authentication required')) {
        const newCookies = await loginToTiParser()
        headers['Cookie'] = newCookies
        wiFilesResponse = await fetch(wiFilesUrl, { headers, method: 'GET' })
      }
    }

    let wiFiles: TiParserFile[] = []
    const storedWiPdfIds: string[] = []
    if (wiFilesResponse.ok) {
      const wiFilesData = await wiFilesResponse.json()
      wiFiles = wiFilesData.files || (Array.isArray(wiFilesData) ? wiFilesData : [])
      console.log(`✅ Found ${wiFiles.length} WI PDF files`)

      // Download and store WI PDFs
      if (wiFiles.length > 0) {
        const BATCH_SIZE = 5
        for (let batchStart = 0; batchStart < wiFiles.length; batchStart += BATCH_SIZE) {
          const batch = wiFiles.slice(batchStart, batchStart + BATCH_SIZE)
          
          await Promise.all(batch.map(async (file) => {
            const docId = file.case_document_id || file.id || file.document_id
            const filename = file.filename || `unknown_${docId}.pdf`
            const owner = file.owner || 'TP'

            try {
              const downloadUrl = `${TIPARSER_BASE_URL}/transcripts/download/wi/${caseNumber}/${docId}`
              let pdfResponse = await fetch(downloadUrl, { headers, method: 'GET' })

              if (pdfResponse.status === 500) {
                const text = await pdfResponse.text()
                if (text.includes('Authentication required')) {
                  const newCookies = await loginToTiParser()
                  headers['Cookie'] = newCookies
                  pdfResponse = await fetch(downloadUrl, { headers, method: 'GET' })
                }
              }

              if (!pdfResponse.ok) {
                console.error(`❌ Failed to download WI ${filename}: ${pdfResponse.status}`)
                return
              }

              const pdfBytes = await pdfResponse.arrayBuffer()
              const storagePath = `wi-transcripts/${caseNumber}/${filename}`
              const pdfBlob = new Blob([pdfBytes], { type: 'application/pdf' })
              
              console.log(`📤 Uploading WI PDF to storage: ${storagePath}`)
              const { data: wiUploadData, error: wiUploadError } = await supabase.storage
                .from('case-pdfs')
                .upload(storagePath, pdfBlob, {
                  contentType: 'application/pdf',
                  upsert: true,
                })
              
              if (wiUploadError) {
                console.error(`❌ Storage upload failed for WI ${filename}:`, wiUploadError)
                throw new Error(`Failed to upload WI PDF to storage: ${wiUploadError.message}`)
              }
              
              console.log(`✅ WI PDF uploaded successfully: ${storagePath}`)

              // Use upsert to prevent duplicates based on case_id + file_name
              console.log(`📝 Upserting WI PDF into bronze_pdf_raw: ${filename}, case_id: ${caseNumber}`)
              const { data: pdfRecord, error: pdfInsertError } = await supabase
                .from('bronze_pdf_raw')
                .upsert({
                  case_id: caseNumber, // TEXT type
                  document_type: 'WI',
                  file_name: filename,
                  storage_path: storagePath,
                  owner: owner,
                  parse_status: 'pending', // ⭐ This should trigger parsing pipeline
                  downloaded_at: new Date().toISOString(),
                }, {
                  onConflict: 'case_id,file_name', // Prevent duplicates
                  ignoreDuplicates: false // Update if exists
                })
                .select('pdf_id, case_id, file_name, parse_status')
                .single()

              if (pdfInsertError) {
                console.error(`❌ Failed to insert WI PDF into bronze_pdf_raw: ${pdfInsertError.message}`)
                console.error(`   Error details: ${JSON.stringify(pdfInsertError)}`)
                console.error(`   Case ID: ${caseNumber}, Filename: ${filename}`)
              } else if (pdfRecord) {
                // Use pdf_id (the actual column name in production)
                const pdfId = pdfRecord.pdf_id
                if (pdfId) {
                  storedWiPdfIds.push(pdfId)
                  totalPdfsStored++
                  console.log(`✅ Stored WI PDF: ${filename} (ID: ${pdfId}, Status: ${pdfRecord.parse_status || 'pending'})`)
                } else {
                  console.error(`❌ WI PDF record missing pdf_id field. Record keys: ${Object.keys(pdfRecord).join(', ')}`)
                  console.error(`   Full record: ${JSON.stringify(pdfRecord)}`)
                }
              } else {
                console.warn(`⚠️ WI PDF insert returned no record and no error for: ${filename}`)
              }

              // Also insert into pdf_documents (with duplicate prevention)
              const extractedYear = extractYearFromFilename(filename)
              const { error: pdfDocError } = await supabase
                .from('pdf_documents')
                .upsert({
                  case_id: caseId,
                  document_type: 'WI',
                  file_name: filename,
                  file_path: storagePath,
                  file_size: pdfBytes.byteLength,
                  tax_year: extractedYear,
                }, {
                  onConflict: 'case_id,file_name', // Prevent duplicates by case + filename
                  ignoreDuplicates: false // Update if exists
                })
              
              if (pdfDocError) {
                console.warn(`⚠️ Failed to upsert WI PDF document: ${pdfDocError.message}`)
              }
            } catch (error) {
              console.error(`❌ Error processing WI PDF ${filename}:`, error)
            }
          }))
        }
      }
    }

    // Step 8: Call TiParser WI Analysis API to parse PDFs and get structured data
    console.log(`🔍 Calling TiParser WI analysis to parse PDFs for case ${caseNumber}...`)
    const wiAnalysisUrl = `${TIPARSER_BASE_URL}/analysis/wi/${caseNumber}`
    
    let wiAnalysisResponse = await fetch(wiAnalysisUrl, {
      headers,
      method: 'GET',
    })

    // If auth error, try logging in again
    if (wiAnalysisResponse.status === 500 || wiAnalysisResponse.status === 401) {
      const text = await wiAnalysisResponse.text()
      if (text.includes('Authentication required') || text.includes('Unauthorized')) {
        console.log('🔐 Re-authenticating for WI analysis...')
        const newCookies = await loginToTiParser()
        headers['Cookie'] = newCookies
        
        wiAnalysisResponse = await fetch(wiAnalysisUrl, {
          headers,
          method: 'GET',
        })
      }
    }

    let wiData: any = null
    if (wiAnalysisResponse.ok) {
      wiData = await wiAnalysisResponse.json()
      console.log(`✅ Got parsed WI data from TiParser analysis`)
      console.log(`   Response keys: ${Object.keys(wiData || {}).join(', ')}`)
      console.log(`   Response structure: ${JSON.stringify(Object.keys(wiData || {})).substring(0, 200)}`)
      
      // Insert WI data into Bronze (this triggers Silver → Gold)
      // Check for various possible response structures
      const hasData = wiData && (
        wiData.forms || 
        wiData.wi_forms || 
        wiData.data || 
        wiData.documents ||
        Array.isArray(wiData) ||
        Object.keys(wiData).length > 0
      )
      
      if (hasData) {
        console.log(`💾 Inserting parsed WI data into Bronze (triggers Silver → Gold)...`)
        console.log(`   Data structure: ${JSON.stringify(wiData).substring(0, 300)}...`)
        
        const { data: bronzeWiResult, error: bronzeWiError } = await supabase
          .from('bronze_wi_raw')
          .insert({
            case_id: caseNumber,
            raw_response: wiData,
          })
          .select('bronze_id')
          .single()

        if (bronzeWiError) {
          console.error(`❌ Failed to insert WI data into Bronze: ${bronzeWiError.message}`)
          console.error(`   Error details: ${JSON.stringify(bronzeWiError)}`)
        } else {
          bronzeWiId = bronzeWiResult.bronze_id
          console.log(`✅ Inserted WI data into Bronze (ID: ${bronzeWiId}) - Silver/Gold triggers should fire automatically`)
        }
      } else {
        console.warn(`⚠️ TiParser WI analysis returned empty or invalid data structure`)
        console.warn(`   Response: ${JSON.stringify(wiData).substring(0, 500)}`)
        console.warn(`   This means WI data will NOT be inserted into Bronze, and Silver/Gold will NOT be populated`)
      }
      
      // ⭐ Update WI PDFs to 'completed' if analysis API call succeeded (even if no data returned)
      if (storedWiPdfIds.length > 0) {
        console.log(`🔄 Attempting to update ${storedWiPdfIds.length} WI PDFs to 'completed' status...`)
        console.log(`   PDF IDs: ${storedWiPdfIds.join(', ')}`)
        
        const { data: updateData, error: updateError } = await supabase
          .from('bronze_pdf_raw')
          .update({ parse_status: 'completed' })
          .in('pdf_id', storedWiPdfIds)
          .select('pdf_id, parse_status')
        
        if (updateError) {
          console.error(`❌ Failed to update WI PDF status: ${updateError.message}`)
          console.error(`   Error details: ${JSON.stringify(updateError)}`)
        } else {
          console.log(`✅ Updated ${updateData?.length || 0} WI PDFs to 'completed' status`)
          if (updateData && updateData.length > 0) {
            console.log(`   Updated IDs: ${updateData.map((r: any) => r.pdf_id || r.bronze_pdf_id || r.id).join(', ')}`)
          }
        }
      } else {
        console.warn(`⚠️ No WI PDF IDs stored - cannot update PDF status. storedWiPdfIds is empty.`)
      }
    } else {
      const errorText = await wiAnalysisResponse.text()
      console.warn(`⚠️ TiParser WI analysis failed: ${wiAnalysisResponse.status} - ${errorText.substring(0, 200)}`)
      
      // ⚠️ If analysis fails, mark PDFs as 'failed' instead of leaving them 'pending'
      if (storedWiPdfIds.length > 0) {
        await supabase
          .from('bronze_pdf_raw')
          .update({ parse_status: 'failed' })
          .in('pdf_id', storedWiPdfIds)
        console.log(`⚠️ Marked ${storedWiPdfIds.length} WI PDFs as 'failed' due to analysis error`)
      }
    }

    // Step 7: Fetch and insert Interview data from CaseHelper
    let interviewBronzeId = null
    try {
      console.log(`📋 Fetching interview data from CaseHelper for case ${caseNumber}...`)
      
      // Check if credentials are configured
      if (!CASEHELPER_USERNAME || !CASEHELPER_PASSWORD) {
        console.warn(`⚠️ CaseHelper credentials not configured (CASEHELPER_USERNAME or CASEHELPER_PASSWORD missing)`)
        console.warn(`   Skipping interview data fetch. Set these env vars in Supabase Dashboard → Functions → ingest-case → Settings`)
      } else {
        const interviewData = await fetchInterviewData(caseNumber)
        
        if (interviewData) {
          console.log(`✅ Fetched interview data, inserting into Bronze...`)
          const { data: interviewBronze, error: interviewError } = await supabase
            .from('bronze_interview_raw')
            .insert({
              case_id: caseNumber, // Use case_number (TEXT)
              raw_response: interviewData,
              api_source: 'casehelper',
              api_endpoint: '/api/cases/{case_id}/interview',
            })
            .select('bronze_id')
            .single()

          if (interviewError) {
            console.error(`❌ Failed to insert interview data: ${interviewError.message}`)
            console.error(`   Error details:`, interviewError)
          } else {
            interviewBronzeId = interviewBronze.bronze_id
            console.log(`✅ Inserted interview data into Bronze (ID: ${interviewBronzeId})`)
            console.log(`   Trigger should fire: bronze_interview_raw → logiqs_raw_data → Gold tables`)
          }
        } else {
          console.log(`ℹ️ No interview data returned from CaseHelper API (404 or empty response)`)
        }
      }
    } catch (interviewErr: any) {
      console.error(`❌ Error fetching/inserting interview data: ${interviewErr.message}`)
      console.error(`   Stack:`, interviewErr.stack)
      // Don't fail the whole request if interview fails
    }

    // Return success response
    return new Response(
      JSON.stringify({
        success: true,
        caseId,
        caseNumber,
        atBronzeId: atBronzeId,
        wiBronzeId: bronzeWiId,
        interviewBronzeId,
        message: 'Ingestion completed successfully',
        filesProcessed: totalPdfsStored, // ⭐ Count of PDFs actually stored
        atDataReceived: !!atData,
        wiDataReceived: !!wiData,
        interviewDataReceived: !!interviewBronzeId,
      }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )

  } catch (error: any) {
    console.error('❌ Error in ingest-case function:', error)
    
    return new Response(
      JSON.stringify({
        error: error.message || 'Internal server error',
        details: error.stack,
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  }
})

// Helper function to login to TiParser
async function loginToTiParser(): Promise<string> {
  if (!LOGIQS_USERNAME || !LOGIQS_PASSWORD) {
    return ''
  }

  try {
    const loginUrl = `${TIPARSER_BASE_URL}/auth/login`
    
    const loginPayloads = [
      { username: LOGIQS_USERNAME, password: LOGIQS_PASSWORD },
      { credentials: { username: LOGIQS_USERNAME, password: LOGIQS_PASSWORD } },
    ]

    for (const payload of loginPayloads) {
      try {
        const response = await fetch(loginUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })

        if (response.ok) {
          // Extract cookies from response
          const cookies = response.headers.get('set-cookie') || ''
          console.log('✅ TiParser login successful')
          return cookies
        }
      } catch (e) {
        continue
      }
    }

    console.warn('⚠️ TiParser login failed')
    return ''
  } catch (error) {
    console.error('❌ Error logging into TiParser:', error)
    return ''
  }
}

// Helper function to extract year from filename
function extractYearFromFilename(filename: string): number | null {
  // Pattern: "AT 23.pdf" or "AT 2023.pdf"
  const match = filename.match(/(?:AT|WI)\s+(\d{2,4})(?:\s|\.)/i)
  if (match) {
    const yearStr = match[1]
    const year = parseInt(yearStr)
    if (year < 100) {
      return 2000 + year
    }
    if (year >= 2000 && year <= 2100) {
      return year
    }
  }
  return null
}

// Helper function to fetch interview data from CaseHelper
async function fetchInterviewData(caseNumber: string): Promise<any | null> {
  if (!CASEHELPER_USERNAME || !CASEHELPER_PASSWORD) {
    console.warn('⚠️ CaseHelper credentials not configured, skipping interview fetch')
    return null
  }

  try {
    // Step 1: Authenticate with CaseHelper
    const loginUrl = `${CASEHELPER_BASE_URL}/v2/auth/login`
    const loginResponse = await fetch(loginUrl, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        credentials: {
          username: CASEHELPER_USERNAME,
          password: CASEHELPER_PASSWORD,
          appType: 'transcript_pipeline',
        },
      }),
    })

    if (!loginResponse.ok) {
      throw new Error(`CaseHelper login failed: ${loginResponse.status}`)
    }

    const loginData = await loginResponse.json()
    const cookies = loginData.cookies || {}
    
    // Build Cookie header
    const cookieParts: string[] = []
    for (const [key, value] of Object.entries(cookies)) {
      if (value) {
        cookieParts.push(`${key}=${value}`)
      }
    }
    const cookieHeader = cookieParts.join('; ')

    // Step 2: Fetch interview data
    const interviewUrl = `${CASEHELPER_BASE_URL}/api/cases/${caseNumber}/interview`
    const headers: Record<string, string> = {
      'Cookie': cookieHeader,
      'accept': 'application/json',
      'Content-Type': 'application/json',
    }

    if (CASEHELPER_API_KEY) {
      headers['X-API-Key'] = CASEHELPER_API_KEY
    }

    const interviewResponse = await fetch(interviewUrl, {
      method: 'GET',
      headers,
    })

    if (interviewResponse.status === 404) {
      console.log(`ℹ️ No interview data found for case ${caseNumber}`)
      return null
    }

    if (!interviewResponse.ok) {
      throw new Error(`Failed to fetch interview: ${interviewResponse.status} - ${await interviewResponse.text()}`)
    }

    const interviewData = await interviewResponse.json()
    console.log(`✅ Fetched interview data for case ${caseNumber}`)
    return interviewData

  } catch (error: any) {
    console.error(`❌ Error fetching interview data: ${error.message}`)
    throw error
  }
}

