*==============================================================================
* 01_globals.do  --  Paths and globals
*==============================================================================
*
* You need to edit TWO paths to your machine:
*
*   $dofiles  ->  the folder that contains this file and all the numbered
*                 do-files (e.g. .../Tran_prelim_presentation_v2/dofiles).
*                 This one is set in 00_master.do, not here.
*
*   $root     ->  the DATA folder that contains raw/, clean/, output/.
*                 The raw folder must contain crea_hpi_Tran.xlsx and the
*                 other source files. This one is set below.
*
* IMPORTANT
*   1. Use FORWARD SLASHES "/", not backslashes "\".
*   2. Do NOT put a "$" in front of the drive letter. Just write "C:/...".
*      A "$" would make Stata try to interpret the next character as a
*      global-macro name and produce a broken path.
*   3. Wrap the whole path in double quotes because it contains spaces.
*
* Correct examples
*   Windows:  global root "C:/Users/YOU/OneDrive - Wilfrid Laurier University/Spring - 2026/EC 481/data"
*   macOS:    global root "/Users/YOU/EC481/data"
*
*==============================================================================


* ----- EDIT THIS LINE ONLY-----------------------------------------------------
global root "C:\Users\Dell\OneDrive - Wilfrid Laurier University\Spring - 2026\EC 481\Term paper\Tran_EC481_submission\code_Tran\data"     // <<< EDIT
* -----------------------------------------------------------------------------


* Derived sub-folders (no edits needed)
global raw    "$root/raw"
global clean  "$root/clean"
global output "$root/output"

capture mkdir "$clean"
capture mkdir "$output"


* -----------------------------------------------------------------------------
* Preflight check: fail loudly if the data folder is not where $root points.
* -----------------------------------------------------------------------------
capture confirm file "$raw/crea_hpi_Tran.xlsx"
if _rc {
    display as error " "
    display as error "*****************************************************"
    display as error "  Stata cannot find crea_hpi_Tran.xlsx in $raw."
    display as error "  Fix the global root line in 01_globals.do so that"
    display as error "  the folder $raw exists and contains crea_hpi_Tran.xlsx."
    display as error "*****************************************************"
    display as error " "
    display as error "  Current resolved paths:"
    display as error "     root   = $root"
    display as error "     raw    = $raw"
    display as error "     clean  = $clean"
    display as error "     output = $output"
    display as error " "
    exit 601
}

display as text " "
display as text "Paths OK:"
display as text "  root   = $root"
display as text "  raw    = $raw"
display as text "  clean  = $clean"
display as text "  output = $output"
display as text " "


* Install packages once; comment out after first successful run.
* ssc install estout,   replace
* ssc install boottest, replace
* ssc install pdslasso, replace
* ssc install ddml,     replace
