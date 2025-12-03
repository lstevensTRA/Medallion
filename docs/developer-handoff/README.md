# Tax Investigation System - Developer Handoff Documentation

**Complete, technology-agnostic specification for rebuilding the Tax Investigation system.**

## Overview

This directory contains 8 comprehensive technical documents that provide everything needed to rebuild the Tax Investigation system from scratch. These documents focus on **business logic and data flows**, not Excel cell references.

**Reference Implementation:** The Excel file "1202864 aTI 2.2.4.xlsx" serves as a working reference to validate calculations, but the system should be built using the business logic documented here, not by replicating Excel cell formulas.

## Documents

### Core Specification (8 Documents)

### 1. [TI_DEPENDENCY_GRAPH.md](./TI_DEPENDENCY_GRAPH.md)
**What data feeds into what calculations**

- Data sources (AT PDFs, WI PDFs, Interview API, AI Glossary, IRS tables)
- Core calculation dependencies (Account Balance, CSED, Income calculations, Tax projections)
- Dependency flow diagrams
- **Key Principle:** Use descriptive names, not cell references

### 2. [RULE_FORMALIZATION_FORMAT.md](./RULE_FORMALIZATION_FORMAT.md)
**How to structure and apply 3,000+ business rules**

- IRS Transaction Code Rules (156 codes)
- Income Document Type Rules (3,247 form variants)
- Data model for rules
- How rules are applied during processing
- Rule version management strategy

### 3. [DATA_MODEL_V1.md](./DATA_MODEL_V1.md)
**Complete logical data model**

- Medallion Architecture (Bronze → Silver → Gold)
- Bronze Layer Entities (raw storage)
- Silver Layer Entities (structured business data)
- Gold Layer Entities (calculated views)
- Entity relationships and data flows

### 4. [API_SPECIFICATION.md](./API_SPECIFICATION.md)
**External APIs and internal API needs**

- TiParser API endpoints (PDF parsing, interview data)
- Internal APIs to build (Case Ingestion, Tax Investigation, Tax Projection, Resolution Options)
- IRS Reference Data APIs (tax brackets, standard deductions, collection standards)

### 5. [PDF_TO_DATA_MODEL_MAPPING.md](./PDF_TO_DATA_MODEL_MAPPING.md)
**How PDF data maps to entities**

- Account Transcript (AT) PDF → Database transformation
- Wage & Income (WI) PDF → Database transformation
- Interview API → Database transformation
- Bronze → Silver → Gold layer examples
- **NO Excel cell references** - pure business logic

### 6. [TRANSFORMATION_PIPELINE.md](./TRANSFORMATION_PIPELINE.md)
**Step-by-step data transformations**

- Phase 1: PDF Acquisition
- Phase 2: PDF Parsing
- Phase 3: Bronze → Silver Transformation
- Phase 4: Silver → Gold Calculation
- Phase 5: Application Access
- Validation against Excel

### 7. [CALCULATION_EXECUTION_GRAPH.md](./CALCULATION_EXECUTION_GRAPH.md)
**Calculation dependencies and execution order**

- Execution Levels (0-7) with dependencies
- Dependency graph visualization
- Parallelization opportunities
- Recalculation triggers
- Performance optimization strategies

### 8. [RULE_VERSIONING_STRATEGY.md](./RULE_VERSIONING_STRATEGY.md)
**How to version business rules over time**

- Why versioning matters
- Versioning data model
- Tax table versioning
- Applying versioned rules
- Audit trail
- Rule change workflow
- Migration strategies

## Reading Order

For a new developer:

1. **Start with:** `TI_DEPENDENCY_GRAPH.md` - Understand what needs to be calculated
2. **Then read:** `DATA_MODEL_V1.md` - Understand the data structure
3. **Then read:** `RULE_FORMALIZATION_FORMAT.md` - Understand how rules work
4. **Then read:** `PDF_TO_DATA_MODEL_MAPPING.md` - See how data flows
5. **Then read:** `TRANSFORMATION_PIPELINE.md` - Understand the process
6. **Then read:** `CALCULATION_EXECUTION_GRAPH.md` - Understand execution order
7. **Then read:** `API_SPECIFICATION.md` - Understand integration points
8. **Finally read:** `RULE_VERSIONING_STRATEGY.md` - Understand maintenance

## Key Principles

1. **Focus on Business Logic, Not Excel**
   - The Excel sheet is a reference implementation, not the specification
   - Build using the business logic documented here
   - Use Excel to validate, not to design

2. **Technology Agnostic**
   - These documents don't prescribe specific technologies
   - Focus on entities, relationships, and data flows
   - Can be implemented in any database/backend/frontend stack

3. **Medallion Architecture**
   - Bronze: Raw, immutable data
   - Silver: Typed, structured data with business rules applied
   - Gold: Calculated views ready for application consumption

4. **Rule-Based Enrichment**
   - All data enrichment comes from business rules (AI Glossary)
   - Rules are versioned and time-aware
   - Calculations are auditable

## Validation

After implementation, validate against:
- Excel file "1202864 aTI 2.2.4.xlsx" (Tax Projection2.0 tab)
- Known test cases with expected results
- IRS publications for tax brackets and deductions

## Questions?

If anything is unclear in these documents:
1. Check the Excel reference implementation
2. Review the dependency graphs
3. Trace through the transformation pipeline examples
4. Consult the calculation execution graph for order

---

## Complete Mapping Guide

- **`TI_SHEET_TO_DATABASE_COMPLETE_MAPPING.md`** - Complete, systematic mapping of every tab, column, cell, and formula from the TI Excel sheet to the database implementation. Includes:
  - Tax Investigation tab mapping
  - AT Raw Data tab mapping
  - WI Raw Data tabs with SSN filtering logic
  - Tax Projection tab calculations
  - AUR Analysis, Levy/Garnishment, Resolution Options tabs
  - Macro functions converted to database equivalents
  - Excel formulas converted to SQL functions
  - Complete data flow diagrams

- **`COMPLETE_EQUATION_REFERENCE.md`** - **NEW:** Comprehensive reference for ALL equation types and calculation patterns used across Tax Investigation sheets. Generic reference applicable to any case. Includes:
  - CSED calculations (base, tolling, adjusted)
  - Tax projection calculations (income, brackets, deductions)
  - Account balance calculations
  - AUR and SFR detection and calculations
  - Income aggregation patterns
  - Resolution options calculations (IA, OIC, CNC)
  - All Excel formula patterns with SQL equivalents
  - Database function implementations
  - Validation checklists
  - **Status:** Complete reference - covers all major equation types

- **`EXTRACT_EXCEL_FORMULAS_SCRIPT.md`** - Instructions and scripts for extracting formulas from Excel files
- **`extract_excel_formulas.py`** - Python script to automatically extract all formulas from Excel file

## Reference Files

Additional supporting documents are included in this folder:

- **`REFERENCE_FILES_README.md`** - Guide to all reference files
- **`AI_GLOSSARY_COLUMN_DOCUMENTATION.md`** - Complete AI Glossary column documentation
- **`AI_GLOSSARY_IMPORT_SUMMARY.md`** - AI Glossary import summary and statistics
- **`ai_glossary_structure.json`** - JSON structure of AI Glossary Excel file
- **`macros.gs`** - Google Apps Script macros from original Excel implementation (reference only)
- **`MAPPING_AND_MACROS_ASSESSMENT.md`** - Assessment of macro implementation status
- **`extract_ai_glossary_seed.py`** - Python script to extract seed data from AI Glossary
- **`AI Glossary.xlsx`** - The master Excel file containing all business rules (385KB)

**Example Case Files:**
- Example case Excel files (e.g., `1273247 aTI 2.2.7.xlsx`) are located in the parent `docs/` directory
- These serve as reference implementations to validate calculations

---

**Last Updated:** December 2, 2025  
**Version:** 1.0  
**Status:** Complete specification ready for implementation

