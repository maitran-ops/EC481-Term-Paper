*==============================================================================
* 06_clean_rates.do  --  BoC 5-yr conventional + OSFI qualifying rate, annual
*------------------------------------------------------------------------------
* Input : $raw/boc_5yr_mortgage_Tran.xlsx sheet chartered_bank_interest
*         (columns: date, V80691335)
* Output: $clean/mortgage_rate_annual_clean_Tran.dta
*==============================================================================

* Pre-check: this raw file is YOUR original BoC/CMHC rate file and must be in
* $raw before running. It is not bundled (see data/raw/_READ_ME_raw_files.txt).
capture confirm file "$raw/boc_5yr_mortgage_Tran.xlsx"
if _rc {
    display as error " "
    display as error "*****************************************************"
    display as error "  MISSING RAW FILE: $raw/boc_5yr_mortgage_Tran.xlsx"
    display as error "  Copy your Bank of Canada / CMHC 5-year mortgage rate"
    display as error "  file into the data/raw folder, then re-run 00_master.do."
    display as error "  (See data/raw/_READ_ME_raw_files.txt for details.)"
    display as error "*****************************************************"
    display as error " "
    exit 601
}

import excel "$raw/boc_5yr_mortgage_Tran.xlsx", ///
    sheet("chartered_bank_interest") firstrow clear allstring
rename *, lower

keep date v80691335
rename v80691335 contract_rate_5yr

foreach v in date contract_rate_5yr {
    replace `v' = strtrim(itrim(`v'))
}
drop if missing(date)
drop if missing(contract_rate_5yr)

* Date parsing (MDY primary, YMD fallback)
gen date_stata = daily(date, "MDY")
replace date_stata = daily(date, "YMD") if missing(date_stata)
format date_stata %td
drop if missing(date_stata)

gen year = year(date_stata)
destring contract_rate_5yr, replace force
drop if missing(contract_rate_5yr)

summ contract_rate_5yr, detail
tab year

* Weekly Wednesday -> annual average
keep if inrange(year, 2016, 2023)
collapse (mean) contract_rate_5yr, by(year)

* OSFI qualifying rate: greater of contract + 2 pp or 5.25 %
gen qual_rate = max(contract_rate_5yr + 2, 5.25)

label var contract_rate_5yr "BoC posted 5-yr conventional mortgage rate, annual avg (%)"
label var qual_rate         "Mortgage qualifying rate: max(contract+2pp, 5.25%)"

list year contract_rate_5yr qual_rate, sep(0)
summ contract_rate_5yr qual_rate

save "$clean/mortgage_rate_annual_clean_Tran.dta", replace
