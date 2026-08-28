*==============================================================================
* 02_clean_hpi.do  --  Clean CREA MLS HPI to one row per (board-market, year)
*------------------------------------------------------------------------------
* Input : $raw/crea_hpi_Tran.xlsx    (one worksheet per CREA board)
* Output: $clean/hpi_annual_clean_Tran.dta
*==============================================================================

* Enumerate worksheets
import excel "$raw/crea_hpi_Tran.xlsx", describe
local nsheets = r(N_worksheet)
forvalues i = 1/`nsheets' {
    local sheet`i' "`r(worksheet_`i')'"
}

tempfile master
local first = 1

forvalues i = 1/`nsheets' {
    local sh "`sheet`i''"
    display as text "Importing sheet: `sh'"

    import excel "$raw/crea_hpi_Tran.xlsx", sheet("`sh'") firstrow clear
    gen market_crea = "`sh'"

    rename Date year
    destring year, replace

    * Composite benchmark price: select BY NAME, not by position.
    * Board worksheets differ in column count (9, 11, or 13 cols) but every
    * board carries a "Composite_Benchmark" column. Positional selection
    * (the old "8th variable" rule) silently grabbed Single_Family_Benchmark
    * or One_Storey_Benchmark on the smaller boards -- an apples-to-oranges bug.
    capture confirm variable Composite_Benchmark
    if _rc {
        display as error "Sheet `sh' has no Composite_Benchmark column; skipped."
        continue
    }
    rename Composite_Benchmark benchmark_price

    keep market_crea year benchmark_price
    order market_crea year benchmark_price

    if `first' == 1 {
        save `master', replace
        local first = 0
    }
    else {
        append using `master'
        save `master', replace
    }
}

use `master', clear

* Restrict to analysis window and clean
keep if inrange(year, 2016, 2023)
destring benchmark_price, replace ignore(", $")
drop if missing(market_crea, year, benchmark_price)

duplicates report market_crea year
collapse (mean) benchmark_price, by(market_crea year)

rename market_crea crea_market
replace crea_market = strtrim(itrim(crea_market))
sort crea_market year

* Panel-coverage diagnostics
tab year
bysort crea_market: gen n_years = _N
tab n_years
drop n_years

save "$clean/hpi_annual_clean_Tran.dta", replace
