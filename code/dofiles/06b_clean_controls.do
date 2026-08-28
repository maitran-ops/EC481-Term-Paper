*==============================================================================
* 06b_clean_controls.do  --  Supply/demand controls for the mechanism check
*------------------------------------------------------------------------------
* Builds three CMA-by-year control series DIRECTLY FROM THE ORIGINAL DOWNLOADS,
* writes out a nicely formatted clean CSV for each (so the construction is fully
* transparent and reproducible), then saves one merged control file.
*
* These controls enter ONLY the exploratory mechanism regressions in
* 09_regressions.do -- never the primary specification -- because they are
* plausibly post-treatment OUTCOMES of the qualifying rate (bad-controls
* concern), and because housing starts is unavailable pre-2023 for the six
* CMAs reclassified under 2021-Census geography (documented below).
*
* ORIGINAL DOWNLOADS (inputs, all under $raw/controls):
*   housing_starts/_original_downloads/34100134.csv
*        StatCan Table 34-10-0134-01 full data cube (all geographies/years).
*   housing_starts/_original_downloads/
*        provincial-starts-completions-dwelling-type-12-2{1,2,3}-en.xlsx
*        CMHC "Housing Information Monthly", December editions. Table A6-1 gives
*        cumulative Jan-Dec starts by CMA; column F ("Total" under "Starts").
*   _original_population_17100148_Tran.csv   StatCan Table 17-10-0148-01.
*   _original_labour_14100461_Tran.csv       StatCan Table 14-10-0461-01.
*
* CLEAN CSVs WRITTEN BY THIS DO-FILE (regenerated every run, never taken as
* given; provided so the reader can inspect exactly what was extracted):
*   housing_starts/starts_2016_2020_Tran.csv, starts_2021/2022/2023_Tran.csv
*   population_clean_Tran.csv, unemp_clean_Tran.csv
*
* FINAL OUTPUT: $clean/controls_cma_clean_Tran.dta
*                 (cma_key year population ln_pop unemp_rate starts_total ln_starts)
*
* WHY starts is split across four files, then appended:
*   StatCan Table 34-10-0134-01 stopped being populated at CMA level after 2022,
*   so 2023 comes from CMHC's Dec-2023 bulletin; 2016-2020 from StatCan; 2021-2023
*   from the CMHC December bulletins (same CMHC Starts and Completions Survey).
*
* KNOWN, DOCUMENTED coverage gap (not a data error):
*   Fredericton, Drummondville, Belleville-Quinte West, Kamloops, Chilliwack, and
*   Nanaimo became CMAs only under 2021-Census geography (Jan 2023); their starts
*   exist for 2023 only. ln_starts is missing for these six in 2016-2022 (42 of
*   288 CMA-years); the FE estimator drops those cells from the starts spec only.
*==============================================================================

local ctrl "$raw/controls"
local sdir "`ctrl'/housing_starts"
local orig "`sdir'/_original_downloads"

* ---------------------------------------------------------------------------
* cma_key normalizer (same rule as 05_clean_income.do / 07_build_panel.do), as
* a program so it is applied identically to every source.
* ---------------------------------------------------------------------------
capture program drop _mk_cma_key
program define _mk_cma_key
    args src
    capture drop cma_key
    gen cma_key = `src'
    replace cma_key = regexs(1) if regexm(cma_key, "^([^,]+),")   // strip ", Province"
    replace cma_key = subinstr(cma_key, "(CMA)", "", .)
    replace cma_key = subinstr(cma_key, "(CA)",  "", .)
    replace cma_key = ustrlower(cma_key)
    foreach ch in "_" "-" "–" "/" "." "'" {
        replace cma_key = subinstr(cma_key, "`ch'", " ", .)
    }
    foreach pair in "é e" "è e" "ê e" "ë e" "à a" "â a" "ô o" "î i" "ï i" "ç c" {
        local a : word 1 of `pair'
        local b : word 2 of `pair'
        replace cma_key = subinstr(cma_key, "`a'", "`b'", .)
    }
    replace cma_key = strtrim(itrim(cma_key))
    replace cma_key = "greater sudbury" if cma_key == "greater sudbury grand sudbury"
end

* ---------------------------------------------------------------------------
* Target CMA-key list (the 36 markets in the panel).
* ---------------------------------------------------------------------------
capture confirm file "$clean/hpi_cma_expanded_Tran.dta"
if !_rc  use "$clean/hpi_cma_expanded_Tran.dta", clear
else     use "$clean/hpi_cma_clean_Tran.dta", clear
_mk_cma_key cma_name
keep cma_key
duplicates drop
sort cma_key
tempfile target_cmas
save `target_cmas', replace

* ==========================================================================
* (1) HOUSING STARTS
* ==========================================================================

* ---- (1a) 2016-2020 from StatCan Table 34-10-0134-01 (original data cube) --
import delimited "`orig'/34100134.csv", clear varnames(1) bindquote(strict) ///
    encoding("utf-8")
rename *, lower
capture rename ref_date year
capture rename housingestimates housing_estimates
capture rename typeofunit type_of_unit
capture rename value starts_total
destring year starts_total, replace ignore(",") force
keep if lower(housing_estimates) == "housing starts"
keep if lower(type_of_unit)      == "total units"
drop if lower(geo) == "census metropolitan areas"     // drop national aggregate
* Split-geography guard: StatCan's cube reports Ottawa-Gatineau as THREE rows
* per year -- "Ottawa-Gatineau, Ontario/Quebec" (the combined CMA total) plus
* "..., Ontario part, Ontario/Quebec" and "..., Quebec part, Ontario/Quebec".
* All three share the same text before the first comma, so the cma_key
* normalizer below would otherwise collapse them into duplicate cma_key-year
* rows (verified: the Ontario-part + Quebec-part values sum exactly to the
* combined total, e.g. 5,298 + 1,819 = 7,117 for 2016, confirming which row
* is correct). Drop the two partial rows and keep only the combined CMA total,
* the same guard 05_clean_income.do already applies for this reason.
drop if strpos(lower(geo), " part") > 0
keep if inrange(year, 2016, 2020)
_mk_cma_key geo
merge m:1 cma_key using `target_cmas'
keep if _merge == 3
drop _merge
keep cma_key year starts_total
gsort cma_key year
preserve
    export delimited using "`sdir'/starts_2016_2020_Tran.csv", replace
restore
tempfile s0
save `s0', replace

* ---- (1b) 2021-2023 from the CMHC December bulletins (Table A6-1) -----------
* CMA name in column A, "Starts Total" in column F. Data-row ranges differ by
* file: Dec-2021 & Dec-2022 = rows 8-44; Dec-2023 = rows 7-49. Import cols A:F
* by explicit cellrange; keep only A (name) and F (total starts).
foreach spec in ///
    "2021 provincial-starts-completions-dwelling-type-12-21-en.xlsx A8:F44" ///
    "2022 provincial-starts-completions-dwelling-type-12-22-en.xlsx A8:F44" ///
    "2023 provincial-starts-completions-dwelling-type-12-23-en.xlsx A7:F49" {

    local yr   : word 1 of `spec'
    local file : word 2 of `spec'
    local rng  : word 3 of `spec'

    import excel "`orig'/`file'", sheet("Table A6_1") cellrange(`rng') clear allstring
    keep A F
    rename A geo
    rename F starts_str
    drop if missing(geo)
    drop if inlist(lower(strtrim(geo)), "cma total", "total", "")
    gen year = `yr'
    destring starts_str, gen(starts_total) ignore(",") force
    drop starts_str
    _mk_cma_key geo
    merge m:1 cma_key using `target_cmas'
    keep if _merge == 3
    drop _merge
    keep cma_key year starts_total
    gsort cma_key year
    preserve
        export delimited using "`sdir'/starts_`yr'_Tran.csv", replace
    restore
    append using `s0'
    save `s0', replace
}

* ---- (1c) finalize starts panel -------------------------------------------
use `s0', clear
keep cma_key year starts_total
drop if missing(cma_key, year)
duplicates report cma_key year
isid cma_key year
* Accuracy asserts against hand-verified source values.
count if cma_key == "toronto"   & year == 2016 & starts_total == 39027
assert r(N) == 1
count if cma_key == "vancouver" & year == 2023 & starts_total == 33244
assert r(N) == 1
count if cma_key == "calgary"   & year == 2022 & starts_total == 17306
assert r(N) == 1
count if cma_key == "ottawa gatineau" & year == 2016 & starts_total == 7117
assert r(N) == 1
gen double ln_starts = ln(starts_total)
label var starts_total "Total housing starts (CMHC/StatCan), all dwelling types"
label var ln_starts    "Log total housing starts"
keep cma_key year starts_total ln_starts
sort cma_key year
tempfile starts_clean
save `starts_clean', replace
display as text "Housing starts built from originals: `=_N' CMA-years."

* ==========================================================================
* (2) POPULATION -- StatCan Table 17-10-0148-01 (original wide export)
* ==========================================================================
* Position-based import (Stata cannot name a variable "2016"): import with no
* header, skip the 11 metadata rows, then map columns 1..9 = geo,2016..2023.
import delimited "`ctrl'/_original_population_17100148_Tran.csv", clear ///
    varnames(nonames) rowrange(12) colrange(1:9) bindquote(strict) encoding("utf-8")
* v1 = geography; v2..v9 = 2016..2023
rename v1 geo
local y = 2016
forvalues c = 2/9 {
    rename v`c' pop`y'
    local ++y
}
keep if strpos(geo, "(CMA)") > 0
drop if strpos(lower(geo), " part") > 0
_mk_cma_key geo
merge m:1 cma_key using `target_cmas'
keep if _merge == 3
drop _merge
keep cma_key pop2016-pop2023
reshape long pop, i(cma_key) j(year)
rename pop population_str
destring population_str, gen(population) ignore(",") force
drop population_str
drop if missing(cma_key, year, population)
isid cma_key year
gen double ln_pop = ln(population)
label var population "CMA population estimate, July 1"
label var ln_pop     "Log CMA population"
count if cma_key == "toronto" & year == 2023 & population > 6000000
assert r(N) == 1
count if cma_key == "ottawa gatineau" & year == 2016 & population == 1407766
assert r(N) == 1
gsort cma_key year
preserve
    export delimited using "`ctrl'/population_clean_Tran.csv", replace
restore
keep cma_key year population ln_pop
sort cma_key year
tempfile pop_clean
save `pop_clean', replace
display as text "Population built from original: `=_N' CMA-years."

* ==========================================================================
* (3) UNEMPLOYMENT -- StatCan Table 14-10-0461-01 (original wide export)
* ==========================================================================
* Year header row 12; CMA data begin row 14 (row 13 is a "Percent" unit row).
* Position-based import, columns 1..9 = geo,2016..2023.
import delimited "`ctrl'/_original_labour_14100461_Tran.csv", clear ///
    varnames(nonames) rowrange(14) colrange(1:9) bindquote(strict) encoding("utf-8")
rename v1 geo
local y = 2016
forvalues c = 2/9 {
    rename v`c' un`y'
    local ++y
}

* Homogenize storage type BEFORE reshape: some year-columns contain the
* suppressed-cell marker "x" (Chilliwack 2017, Drummondville 2022) and import
* as string, while columns with no suppression import as numeric. reshape
* needs one consistent type across un2016-un2023, so destring them all now;
* "x" becomes missing via force.
destring un2016-un2023, replace force

drop if missing(geo)
* Same split-geography guard as population/starts: the labour cube reports
* Ottawa-Gatineau as three rows ("Ontario/Quebec" combined, "Ontario part",
* "Quebec part"), all sharing the same text before the first comma. Keep only
* the combined row.
drop if strpos(lower(geo), " part") > 0
_mk_cma_key geo
merge m:1 cma_key using `target_cmas'
keep if _merge == 3
drop _merge
keep cma_key un2016-un2023
reshape long un, i(cma_key) j(year)

rename un unemp_rate

drop if missing(cma_key, year)          // keep rows even if unemp_rate missing
isid cma_key year
label var unemp_rate "Unemployment rate, 15+, annual (%)"
count if cma_key == "toronto" & year == 2020 & abs(unemp_rate - 11.0) < 0.01
assert r(N) == 1
count if cma_key == "ottawa gatineau" & year == 2016 & abs(unemp_rate - 6.5) < 0.01
assert r(N) == 1
gsort cma_key year
preserve
    export delimited using "`ctrl'/unemp_clean_Tran.csv", replace
restore
keep cma_key year unemp_rate
sort cma_key year
tempfile unemp_clean
save `unemp_clean', replace
display as text "Unemployment built from original: `=_N' CMA-years."

* ==========================================================================
* (4) Merge the three controls into one file keyed by cma_key x year
* ==========================================================================
use `pop_clean', clear
merge 1:1 cma_key year using `unemp_clean', nogen
merge 1:1 cma_key year using `starts_clean'
tab _merge
drop _merge
order cma_key year population ln_pop unemp_rate starts_total ln_starts
sort cma_key year
count
count if !missing(ln_starts)
display as text "Controls file: `r(N)' CMA-years with non-missing housing starts."
save "$clean/controls_cma_clean_Tran.dta", replace
display as text "Saved $clean/controls_cma_clean_Tran.dta"
