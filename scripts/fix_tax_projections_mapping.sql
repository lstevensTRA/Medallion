-- Fix tax_projections population to use correct column names from calculate_tax_projection
-- The function returns: total_income, se_income, non_se_income, se_taxable_earnings, se_social_security, 
-- se_medicare, early_withdrawal_penalty, income_tax, total_tax, withholding, projected_balance

CREATE OR REPLACE FUNCTION populate_tax_projections_for_case(p_case_id UUID)
RETURNS VOID AS $$
DECLARE
    v_tax_year RECORD;
    v_tax_year_id UUID;
    v_filing_status TEXT;
    v_owner TEXT;
    v_tax_period TEXT;
    v_projection RECORD;
BEGIN
    -- Loop through all tax years for this case
    FOR v_tax_year IN
        SELECT id, year, owner, filing_status
        FROM tax_years
        WHERE case_id = p_case_id
        ORDER BY year DESC, owner
    LOOP
        v_tax_year_id := v_tax_year.id;
        v_filing_status := COALESCE(v_tax_year.filing_status, 'Single');
        v_owner := COALESCE(v_tax_year.owner, 'TP');
        
        -- Create tax_period string (e.g., "2024-TP", "2024-S", "2024")
        IF v_owner IN ('TP', 'S') THEN
            v_tax_period := v_tax_year.year::TEXT || '-' || v_owner;
        ELSE
            v_tax_period := v_tax_year.year::TEXT;
        END IF;
        
        -- Calculate projection using existing function
        BEGIN
            SELECT * INTO v_projection
            FROM calculate_tax_projection(
                p_case_id,
                v_tax_year.year,
                v_owner,
                v_filing_status
            );
            
            -- Insert or update tax_projections with CORRECT column mapping
            INSERT INTO tax_projections (
                case_id,
                tax_period,
                tp_income,
                tp_withholding,
                spouse_income,
                spouse_withholding,
                combined_income,
                combined_withholding,
                projected_tax,
                projected_refund_or_owed
            )
            VALUES (
                p_case_id,
                v_tax_period,
                CASE WHEN v_owner = 'TP' THEN v_projection.total_income ELSE 0 END,
                CASE WHEN v_owner = 'TP' THEN v_projection.withholding ELSE 0 END,
                CASE WHEN v_owner = 'S' THEN v_projection.total_income ELSE 0 END,
                CASE WHEN v_owner = 'S' THEN v_projection.withholding ELSE 0 END,
                v_projection.total_income,  -- combined_income
                v_projection.withholding,   -- combined_withholding
                v_projection.total_tax,    -- projected_tax (FIXED: was projected_tax_liability)
                v_projection.projected_balance  -- projected_refund_or_owed (FIXED: was projected_refund_or_due)
            )
            ON CONFLICT (case_id, tax_period) DO UPDATE SET
                tp_income = EXCLUDED.tp_income,
                tp_withholding = EXCLUDED.tp_withholding,
                spouse_income = EXCLUDED.spouse_income,
                spouse_withholding = EXCLUDED.spouse_withholding,
                combined_income = EXCLUDED.combined_income,
                combined_withholding = EXCLUDED.combined_withholding,
                projected_tax = EXCLUDED.projected_tax,
                projected_refund_or_owed = EXCLUDED.projected_refund_or_owed,
                updated_at = NOW();
                
        EXCEPTION WHEN OTHERS THEN
            -- If function doesn't exist or fails, use fallback calculation
            RAISE WARNING 'calculate_tax_projection failed for year %: %', v_tax_year.year, SQLERRM;
            
            -- Fallback: Calculate from income_documents directly
            INSERT INTO tax_projections (
                case_id,
                tax_period,
                tp_income,
                tp_withholding,
                spouse_income,
                spouse_withholding,
                combined_income,
                combined_withholding,
                projected_tax,
                projected_refund_or_owed
            )
            SELECT
                p_case_id,
                v_tax_period,
                COALESCE(SUM(CASE WHEN ty.owner = 'TP' THEN id.gross_amount ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN ty.owner = 'TP' THEN id.federal_withholding ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN ty.owner = 'S' THEN id.gross_amount ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN ty.owner = 'S' THEN id.federal_withholding ELSE 0 END), 0),
                COALESCE(SUM(id.gross_amount), 0),
                COALESCE(SUM(id.federal_withholding), 0),
                0, -- Will calculate later
                0  -- Will calculate later
            FROM income_documents id
            JOIN tax_years ty ON id.tax_year_id = ty.id
            WHERE ty.id = v_tax_year_id
              AND ty.case_id = p_case_id
            ON CONFLICT (case_id, tax_period) DO UPDATE SET
                tp_income = EXCLUDED.tp_income,
                tp_withholding = EXCLUDED.tp_withholding,
                spouse_income = EXCLUDED.spouse_income,
                spouse_withholding = EXCLUDED.spouse_withholding,
                combined_income = EXCLUDED.combined_income,
                combined_withholding = EXCLUDED.combined_withholding,
                updated_at = NOW();
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION populate_tax_projections_for_case IS 'Populate tax_projections table for all tax years in a case - FIXED column mapping';

