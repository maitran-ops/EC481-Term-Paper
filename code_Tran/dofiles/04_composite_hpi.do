*==============================================================================
* 04_composite_hpi.do  --  Household-weighted composite HPI for multi-board CMAs
*------------------------------------------------------------------------------
* Method (Progress Meeting 2 direction)
*   Some baseline CMAs are served by more than one CREA board whose footprints
*   partially overlap the CMA (Toronto, Vancouver, Kitchener-Cambridge-Waterloo,
*   Barrie). A single board misses part of the CMA; a plain average over-weights
*   small boards. Build a household-weighted composite:
*
*       HPI_ct = sum over b in c of  w_bc * HPI_bt,      sum(w_bc) = 1
*
*   w_bc = share of CMA c's occupied private dwellings inside board b's
*   footprint (proxy for households). Weights live in household_weights.xlsx,
*   documented in crosswalk_key_Tran.xlsx (sheet Composite_Weights).
*
* Inputs
*   $dofiles/household_weights.xlsx   (cma_name, crea_market, weight)
*   $clean/hpi_annual_clean_Tran.dta
* Output
*   $clean/hpi_composite_by_cma_Tran.dta   (one row per multi-board CMA-year)
*
* Fallback
*   If household_weights.xlsx is missing, exit quietly and let the baseline
*   one-board-per-CMA sample stand. Re-run after adding the file to fold in
*   composite HPI.
*
* CAVEAT
*   Composite weights are APPROXIMATE (public board-coverage pages + 2021
*   census dwelling counts), pending CREA's official boundary shapefile.
*==============================================================================

capture confirm file "$dofiles/household_weights.xlsx"
if _rc {
    display as text ""
    display as text "*****************************************************"
    display as text "  Skipping composite HPI: household_weights.xlsx not found"
    display as text "  in $dofiles. Baseline uses one board per CMA."
    display as text "*****************************************************"
    display as text ""
    exit 0
}

* -------------------------- Load weights ------------------------------------
import excel "$dofiles/household_weights.xlsx", firstrow clear
rename *, lower

keep cma_name crea_market weight
foreach v in cma_name crea_market {
    replace `v' = strtrim(itrim(`v'))
}
destring weight, replace force
drop if missing(cma_name, crea_market, weight)

* Sanity: weights sum to 1 within each CMA
bysort cma_name: egen wsum = total(weight)
assert abs(wsum - 1) < 0.01
drop wsum

tempfile weights
save `weights', replace

* -------------------------- Merge weights with HPI --------------------------
use "$clean/hpi_annual_clean_Tran.dta", clear
replace crea_market = strtrim(itrim(crea_market))

merge m:1 crea_market using `weights'
* _merge==2 => a weight row whose board has no HPI series; report and drop
list crea_market cma_name weight if _merge == 2
keep if _merge == 3
drop _merge

* Weighted composite
gen weighted_price = weight * benchmark_price
collapse (sum) benchmark_price_composite = weighted_price, by(cma_name year)

label var benchmark_price_composite "Household-weighted composite HPI benchmark price"

* Diagnostic: composite should sit between the min and max board price it blends
sort cma_name year
list cma_name year benchmark_price_composite if inlist(year,2016,2021,2023), sepby(cma_name)

save "$clean/hpi_composite_by_cma_Tran.dta", replace

display as text ""
display as text "Composite HPI written for multi-board CMAs."
display as text ""
