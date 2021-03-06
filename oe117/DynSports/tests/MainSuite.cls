/*------------------------------------------------------------------------
    File        : MainSuite
    Syntax      :
    Author(s)   : dugrau@progress.com
    Created     : Tue May 30 10:49:59 EDT 2017
    Notes       :
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.

block-level on error undo, throw.

@TestSuite(classes="tests.StartupTests").
@TestSuite(classes="tests.ServiceTests").
@TestSuite(classes="tests.ParameterTests").
@TestSuite(classes="tests.UtilityTests").
@TestSuite(classes="tests.FilterTests").
@TestSuite(classes="tests.EntityTests").

class tests.MainSuite:

end class.