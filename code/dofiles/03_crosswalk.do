*==============================================================================
* 03_crosswalk.do  --  CREA -> CMA crosswalk, merge into HPI panel
*------------------------------------------------------------------------------
* Input : $raw/crosswalk_Tran.xlsx sheet Final_Crosswalk
*         $clean/hpi_annual_clean_Tran.dta
* Output: $clean/crosswalk_final_Tran.dta
*         $clean/hpi_cma_clean_Tran.dta   (baseline 31-market HPI panel)
*==============================================================================

* -------------------------- Import crosswalk --------------------------------
import excel "$raw/crosswalk_Tran.xlsx", ///
    sheet("Final_Crosswalk") firstrow clear allstring

ds
local vlist `r(varlist)'
local nvars : word count `vlist'
if `nvars' < 8 {
    display as error "ERROR: crosswalk.xlsx has fewer than 8 columns. Check the Final_Crosswalk sheet."
    exit 198
}

* Positional renaming: 1 CREA Market, 2 Tier, 3 CMA, 4 Province, 5 Method,
*                     6 Baseline, 7 Principal City, 8 Notes
local i = 1
foreach nm in crea_market match_tier cma_name province match_method ///
              baseline_sample principal_city notes {
    local vv : word `i' of `vlist'
    rename `vv' `nm'
    local ++i
}

* -------------------------- Clean text columns ------------------------------
foreach var in crea_market match_tier cma_name province match_method ///
               baseline_sample principal_city notes {
    replace `var' = strtrim(itrim(`var'))
}
drop if missing(crea_market)

foreach var in cma_name principal_city {
    replace `var' = "" if inlist(`var', "—", "-")
}
replace province = upper(province)
replace baseline_sample = upper(baseline_sample)

* -------------------------- Baseline flag -----------------------------------
gen keep_baseline = .
replace keep_baseline = 1 if baseline_sample == "YES"
replace keep_baseline = 0 if baseline_sample == "NO"
tab baseline_sample keep_baseline, missing

* -------------------------- Match quality -----------------------------------
gen match_quality = ""
replace match_quality = "exact_name"    if match_tier == "Tier 1"
replace match_quality = "pip_confirmed" if match_tier == "Tier 2"
replace match_quality = "manual_anchor" if match_tier == "Tier 3"
replace match_quality = "excluded"      if match_tier == "Excluded"

* Robustness: catch spacing/case variants
replace match_quality = "exact_name"    if missing(match_quality) & strpos(lower(match_tier),"tier 1")>0
replace match_quality = "pip_confirmed" if missing(match_quality) & strpos(lower(match_tier),"tier 2")>0
replace match_quality = "manual_anchor" if missing(match_quality) & strpos(lower(match_tier),"tier 3")>0
replace match_quality = "excluded"      if missing(match_quality) & strpos(lower(match_tier),"excluded")>0

tab match_tier
tab match_quality
tab match_tier keep_baseline

* Duplicates
duplicates report crea_market
duplicates report cma_name if keep_baseline == 1

order crea_market cma_name province match_tier match_quality match_method ///
      keep_baseline baseline_sample principal_city notes
sort keep_baseline province cma_name crea_market

save "$clean/crosswalk_final_Tran.dta", replace


* ============== Merge crosswalk into HPI to build 31-market baseline ========
use "$clean/hpi_annual_clean_Tran.dta", clear
replace crea_market = strtrim(itrim(crea_market))

merge m:1 crea_market using "$clean/crosswalk_final_Tran.dta"
tab _merge
list crea_market year benchmark_price if _merge == 1, sepby(crea_market)
list crea_market cma_name match_tier keep_baseline if _merge == 2

keep if _merge == 3
drop _merge

* Baseline sample only
keep if keep_baseline == 1

* Diagnostic counts
egen tag_market = tag(crea_market)
count if tag_market == 1
tab match_tier if tag_market == 1
tab province   if tag_market == 1
drop tag_market

* Panel coverage
tab year
bysort crea_market: egen n_years = count(year)
tab n_years
list crea_market cma_name n_years if n_years != 10, sepby(crea_market)
drop n_years

* Panel identifier
gen ln_benchmark_price = ln(benchmark_price)
capture label drop market_id
egen market_id = group(cma_name province), label(market_id, replace)
xtset market_id year
xtdescribe

order crea_market cma_name province year benchmark_price ln_benchmark_price ///
      match_tier match_quality match_method keep_baseline principal_city ///
      notes market_id
sort cma_name year

save "$clean/hpi_cma_clean_Tran.dta", replace
