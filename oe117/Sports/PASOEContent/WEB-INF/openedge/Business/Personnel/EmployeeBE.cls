/*------------------------------------------------------------------------
    File        : EmployeeBE.cls
    Author(s)   : Code Wizard
    Created     : 12/12/17
    Notes       : Customized BE instance with AFP features available.
  ----------------------------------------------------------------------*/

@program FILE(name="EmployeeBE.cls", module="AppServer").
@openapi.openedge.export FILE(type="REST", executionMode="singleton", useReturnValue="false", writeDataSetBeforeImage="false").
@progress.service.resource FILE(name="employee", URI="/employee", schemaName="dsEmployee", schemaFile="Sports/PASOEContent/WEB-INF/openedge/Common/employee.i").

using Progress.Lang.* from propath.

block-level on error undo, throw.

class Business.Personnel.EmployeeBE inherits Spark.Core.Service.SparkEntity use-widget-pool:

    {Common/employee.i}

    constructor public EmployeeBE ( ):
        ProDataSet = dataset dsEmployee:handle.

        /* Data Source for each table in dataset. Should be in table order as defined in DataSet */
        extent(DataSourceArray) = 1.
        create data-source DataSourceArray[1].
        DataSourceArray[1]:add-source-buffer(buffer Employee:handle, ?).
        ProDataSource = DataSourceArray.

        /* Skip-list entries for each table in dataset. Should be in temp-table order as defined in DataSet. */
        /* Each skip-list entry is a comma-separated list of field names, to be ignored in create statement. */
        extent(SkipListArray) = 1.
        SkipListArray[1] = "".
        SkipList = SkipListArray.
    end constructor.


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="true").
    @progress.service.resourceMapping(type="REST", operation="read", URI="?filter=~{filter~}", alias="", mediaType="application/json").
    @openapi.openedge.method.property(name="mappingType", value="AFP").
    @openapi.openedge.method.property(name="capabilities", value="filter,top,skip,id,sort,orderBy").
    method public void ReadEmployee ( input  filter  as character,
                                      output dataset dsEmployee ):
        define variable iNumRecs as int64 no-undo.
        super:ReadData(filter, iNumRecs, output dataset dsEmployee by-reference).
    end method. /* ReadEmployee */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="true").
    @progress.service.resourceMapping(type="REST", operation="submit", URI="/submit", alias="submit", mediaType="application/json").
    method public void SubmitEmployee ( input-output dataset dsEmployee ):
        super:SubmitData(input-output dataset dsEmployee by-reference).
    end method. /* SubmitEmployee */


    @openapi.openedge.export(type="REST", useReturnValue="false", writeDataSetBeforeImage="false").
    @progress.service.resourceMapping(type="REST", operation="count", URI="/count?filter=~{filter~}", alias="count", mediaType="application/json").
    method public void getCount ( input filter as character, output numRecs as integer ):
        assign numRecs = integer(super:getRecCount(filter)).
    end method. /* getCount */

end class.
