*==============================================================================
* 05_clean_income.do  --  T1FF median census-family income by CMA
*------------------------------------------------------------------------------
* Input : $raw/t1ff_income_Tran.csv  (StatCan Table 11-10-0017-01 export)
*         $clean/hpi_cma_clean_Tran.dta   (target CMA list)
* Output: $clean/income_cma_clean_Tran.dta
*==============================================================================

* -------------------------- Build target CMA-key list -----------------------
* Use the widest HPI panel available so income is kept for ALL markets, baseline (31) or expanded (36). Without this, expansion markets' income is filtered out and the expanded panel collapses back to 31 at the merge.
capture confirm file "$clean/hpi_cma_expanded_Tran.dta"
if !_rc {
    use "$clean/hpi_cma_expanded_Tran.dta", clear
}
else {
    use "$clean/hpi_cma_clean_Tran.dta", clear
}
capture drop cma_key
gen cma_key = cma_name

* Normalization: lowercase, replace punctuation with spaces, strip accents
replace cma_key = ustrlower(cma_key)
replace cma_key = subinstr(cma_key, "_", " ", .)
replace cma_key = subinstr(cma_key, "-", " ", .)
replace cma_key = subinstr(cma_key, "–", " ", .)
replace cma_key = subinstr(cma_key, "/", " ", .)
replace cma_key = subinstr(cma_key, ".", " ", .)
replace cma_key = subinstr(cma_key, "'", " ", .)
replace cma_key = subinstr(cma_key, "é", "e", .)
replace cma_key = subinstr(cma_key, "è", "e", .)
replace cma_key = subinstr(cma_key, "ê", "e", .)
replace cma_key = subinstr(cma_key, "ë", "e", .)
replace cma_key = subinstr(cma_key, "à", "a", .)
replace cma_key = subinstr(cma_key, "â", "a", .)
replace cma_key = subinstr(cma_key, "ô", "o", .)
replace cma_key = subinstr(cma_key, "î", "i", .)
replace cma_key = subinstr(cma_key, "ï", "i", .)
replace cma_key = subinstr(cma_key, "ç", "c", .)
replace cma_key = strtrim(itrim(cma_key))

* Manual: crosswalk uses "Greater Sudbury / Grand Sudbury"; T1FF uses "Greater Sudbury"
replace cma_key = "greater sudbury" if cma_key == "greater sudbury grand sudbury"

keep cma_key
duplicates drop
sort cma_key

tempfile target_cmas
save `target_cmas', replace

* -------------------------- Import T1FF -------------------------------------
* Prefer the full StatCan export if present; otherwise fall back to the slim
* extract bundled with this package (same rows the pipeline reads, ~0.3 MB).
local t1ff_full "$raw/t1ff_income_Tran.csv"
local t1ff_slim "$raw/t1ff_income_Tran_slim.csv"
capture confirm file "`t1ff_full'"
if !_rc {
    local t1ff_use "`t1ff_full'"
    display as text "Using full T1FF file: `t1ff_full'"
}
else {
    capture confirm file "`t1ff_slim'"
    if !_rc {
        local t1ff_use "`t1ff_slim'"
        display as text "Full T1FF not found; using bundled slim extract: `t1ff_slim'"
    }
    else {
        display as error "No T1FF income file found in $raw (neither full nor slim)."
        exit 601
    }
}
import delimited "`t1ff_use'", clear varnames(1) ///
    bindquote(strict) encoding("utf-8")
rename *, lower

* Standardize field names
capture confirm variable ref_date
if !_rc rename ref_date year
capture confirm variable refdate
if !_rc rename refdate year

capture confirm variable value
if !_rc rename value median_income

capture confirm variable geo
if _rc {
    display as error "ERROR: GEO variable not found."
    exit 198
}
capture confirm variable statistics
if _rc {
    display as error "ERROR: Statistics variable not found."
    exit 198
}

* Locate the two dimension columns (varies by StatCan export)
local famtypevar ""
local compvar ""
foreach v in censusfamilytype census_family_type {
    capture confirm variable `v'
    if !_rc local famtypevar `v'
}
foreach v in familytypecomposition family_type_composition {
    capture confirm variable `v'
    if !_rc local compvar `v'
}
if "`famtypevar'" == "" | "`compvar'" == "" {
    display as error "ERROR: Could not locate family-type dimension columns."
    ds
    exit 198
}

* -------------------------- Keep target income concept ----------------------
destring year median_income, replace ignore(",") force

keep if lower(`famtypevar') == "all census families"
keep if lower(`compvar')   == "family types with or without children"
keep if lower(statistics)  == "median before-tax family income"

* -------------------------- Drop rollups and split parts --------------------
keep if strpos(geo, ",") > 0                  // require a comma -> CMA/CA rows
drop if strpos(lower(geo), " part") > 0       // drop provincial parts of split CMAs
drop if strpos(lower(geo), "non cma-ca") > 0
drop if strpos(lower(geo), "non cma") > 0

* -------------------------- Clean CMA name/key ------------------------------
gen cma_name_income = geo
replace cma_name_income = regexs(1) if regexm(cma_name_income, "^([^,]+),")
replace cma_name_income = strtrim(itrim(cma_name_income))

gen cma_key = cma_name_income
replace cma_key = ustrlower(cma_key)
replace cma_key = subinstr(cma_key, "_", " ", .)
replace cma_key = subinstr(cma_key, "-", " ", .)
replace cma_key = subinstr(cma_key, "–", " ", .)
replace cma_key = subinstr(cma_key, "/", " ", .)
replace cma_key = subinstr(cma_key, ".", " ", .)
replace cma_key = subinstr(cma_key, "'", " ", .)
replace cma_key = subinstr(cma_key, "é", "e", .)
replace cma_key = subinstr(cma_key, "è", "e", .)
replace cma_key = subinstr(cma_key, "ê", "e", .)
replace cma_key = subinstr(cma_key, "ë", "e", .)
replace cma_key = subinstr(cma_key, "à", "a", .)
replace cma_key = subinstr(cma_key, "â", "a", .)
replace cma_key = subinstr(cma_key, "ô", "o", .)
replace cma_key = subinstr(cma_key, "î", "i", .)
replace cma_key = subinstr(cma_key, "ï", "i", .)
replace cma_key = subinstr(cma_key, "ç", "c", .)
replace cma_key = strtrim(itrim(cma_key))

* -------------------------- Restrict to baseline CMAs ----------------------
merge m:1 cma_key using `target_cmas'
tab _merge
list cma_key if _merge == 2
keep if _merge == 3
drop _merge

* -------------------------- Finalize ---------------------------------------
keep if inrange(year, 2016, 2023)
keep cma_name_income cma_key year median_income geo
drop if missing(cma_key, year, median_income)

* Diagnose duplicates
duplicates report cma_key year
collapse (mean) median_income, by(cma_name_income cma_key year)
isid cma_key year

* Sanity: dollars, not thousands
summ median_income, detail
list cma_name_income year median_income if median_income < 1000

sort cma_key year
save "$clean/income_cma_clean_Tran.dta", replace
