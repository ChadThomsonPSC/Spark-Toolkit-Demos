/*------------------------------------------------------------------------
    File        : OEMetrics
    Purpose     : Gather and report OE metrics for the current PAS instance
    Description : Utilizes JMX or OEManager queries to get PAS metrics
    Author(s)   : Dustin Grau (dugrau@progress.com)
    Created     : Wed Apr 25 13:58:59 EDT 2018
    Notes       : Provides front-end methods to enable/disable features for
                  tracking metrics in a PASOE environment. For ABLObjects
                  the report must be requested at an application boundary,
                  meaning a point at the end of a request where all normal
                  cleanup has been performed and before the session is made
                  available for the next request. Depends on a configuration
                  file at CATALINA_BASE/bin/metrics_config.json to run the
                  necessary features. The name of this file is set in the
                  related metrics_setenv.[bat|sh] files which must also be
                  placed in the CATALINA_BASE/bin directory.
  ----------------------------------------------------------------------*/

using Progress.Lang.* from propath.
using Progress.Json.ObjectModel.* from propath.
using OpenEdge.Core.Assert from propath.
using OpenEdge.Logging.* from propath.
using Spark.Diagnostic.Util.RemoteMetrics from propath.

block-level on error undo, throw.

class Spark.Diagnostic.Util.OEMetrics inherits Spark.Diagnostic.Util.Logger use-widget-pool final:

    define private variable dLastReportOutput as datetime no-undo initial ?.

    /*** Static Instance ***/

    define public static property Instance as Spark.Diagnostic.Util.OEMetrics no-undo
        get():
            if not valid-object(Instance) then
                assign Instance = new Spark.Diagnostic.Util.OEMetrics().
            return Instance.
        end get.
        private set.

    /*** Common Properties ***/

    /* Property to allow sychronization of timestamps on output generation. */
    define private property OutputTime as datetime no-undo initial ? get. set.

    define private property RequestCount as integer no-undo initial 0 get. set.

    define private property RequestStart as datetime-tz no-undo initial ? get. set.

    define private property oMetricsLogger as ILogWriter no-undo
        get():
            /* Obtain the propper ILogWriter instance for this class. */
            if session:current-request-info:AgentId eq ? then
                /* When no AgentID is available, just use a single bucket. */
                return LoggerBuilder:GetLogger("AgentMetrics").
            else
                /* Otherwise use the standard logger for the OEMetrics class. */
                return this-object:oLogger.
        end get.
        private set.

    define private property oConfig as Spark.Diagnostic.Util.OEMetricsConfig no-undo
        get():
            if oConfig eq ? or not valid-object(oConfig) then
                assign oConfig = new Spark.Diagnostic.Util.OEMetricsConfig(oMetricsLogger).
            else if valid-object(oConfig) then
                oConfig:SetLogger(oMetricsLogger). /* Set the appropriate ILogWriter instance. */

            if not valid-object(oConfig) then
                oMetricsLogger:Error("Unable to create OEMetricsConfig instance.").

            return oConfig.
        end get.
        set.

    define private property oRemoteMetrics as RemoteMetrics no-undo
        get():
            if oRemoteMetrics eq ? or not valid-object(oRemoteMetrics) then
                assign oRemoteMetrics = new RemoteMetrics(oConfig:RemoteSource).
            return oRemoteMetrics.
        end get.
        set.


    /***** Constructor/Destructor *****/


    constructor public OEMetrics ( ):
        super().

        /* Make sure we have a consistent path for temporary files. */
        os-create-dir value(substitute("&1", this-object:TemporaryDir)).
        os-create-dir value(substitute("&1/metrics", this-object:TemporaryDir)).

        /* Make sure any necessary subdirectories are created. */
        os-create-dir value(substitute("&1/metrics/ABLObjects", this-object:TemporaryDir)).
        os-create-dir value(substitute("&1/metrics/ProfilerData", this-object:TemporaryDir)).
        os-create-dir value(substitute("&1/metrics/Requests", this-object:TemporaryDir)).
        os-create-dir value(substitute("&1/metrics/SessionData", this-object:TemporaryDir)).
    end constructor.


    destructor OEMetrics ( ):
        delete object oConfig no-error.
        delete object oLogger no-error.
        delete object oRemoteMetrics no-error.
        delete object Instance no-error.
    end destructor.


    /***** Private Methods *****/


    method private character GetRequestPath ( input piAgentID as integer ):
        define variable cBasePath as character no-undo.

        /* Assemble base path for output and create any needed directories. */
        assign cBasePath = substitute("&1/metrics/Requests/&2", this-object:TemporaryDir, piAgentID).
        os-create-dir value(cBasePath).

        if this-object:OutputTime ne ? then
            return substitute("&1/&2.&3_A&4.json",
                              cBasePath,
                              iso-date(date(this-object:OutputTime)),
                              mtime(this-object:OutputTime), piAgentID).
        else
            return substitute("&1/&2.&3_A&4.json",
                              cBasePath,
                              iso-date(today),
                              mtime(now), piAgentID).
    end method. /* GetRequestPath */


    method private character GetSessionPath ( input piAgentID as integer ):
        define variable cBasePath as character no-undo.

        /* Assemble base path for output and create any needed directories. */
        assign cBasePath = substitute("&1/metrics/SessionData/&2", this-object:TemporaryDir, piAgentID).
        os-create-dir value(cBasePath).

        if this-object:OutputTime ne ? then
            return substitute("&1/&2.&3_A&4.json",
                              cBasePath,
                              iso-date(date(this-object:OutputTime)),
                              mtime(this-object:OutputTime), piAgentID).
        else
            return substitute("&1/&2.&3_A&4.json",
                              cBasePath,
                              iso-date(today),
                              mtime(now), piAgentID).
    end method. /* GetSessionPath */


    method private character GetObjectsPath ( input piAgentID   as integer,
                                              input piSessionID as integer ):
        define variable cBasePath as character no-undo.

        /* Assemble base path for output and create any needed directories. */
        assign cBasePath = substitute("&1/metrics/ABLObjects/&2", this-object:TemporaryDir, piAgentID).
        os-create-dir value(cBasePath).

        if this-object:OutputTime ne ? then
            return substitute("&1/&2.&3_A&4_S&5.json",
                              cBasePath,
                              iso-date(date(this-object:OutputTime)),
                              mtime(this-object:OutputTime), piAgentID, piSessionID).
        else
            return substitute("&1/&2.&3_A&4_S&5.json",
                              cBasePath,
                              iso-date(today),
                              mtime(now), piAgentID, piSessionID).
    end method. /* GetObjectsPath */


    method private logical InMatchList ( input pcCompare as character,
                                         input pcMatches as character ):
        /* Check if value matches something in the list. */
        define variable ix as integer no-undo.
        do ix = 1 to num-entries(pcMatches):
            if pcCompare matches entry(ix, pcMatches) then
                return true.
        end. /* do ix */

        return false.
    end method. /* InMatchList */


    method private OERequestInfo GetRequestInfo ( ):
        return cast(session:current-request-info, OERequestInfo).
    end method. /* GetRequestInfo */


    method private character GetProcedureName ( ):
        define variable oRequestInfo as OERequestInfo no-undo.

        assign oRequestInfo = this-object:GetRequestInfo().
        if valid-object(oRequestInfo) then
            return oRequestInfo:ProcedureName.

        return "".

        finally:
            delete object oRequestInfo no-error.
        end finally.
    end method. /* GetProcedureName */


    method private integer GetAgentID ( ):
        define variable oRequestInfo as OERequestInfo no-undo.
        define variable iAgentID     as int64         no-undo.

        assign oRequestInfo = this-object:GetRequestInfo().
        if valid-object(oRequestInfo) then
            assign iAgentID = oRequestInfo:AgentId.

        /* Fallback for getting current PID from OS. */
        if iAgentID eq ? then do on error undo, leave:
            define variable hProc as handle no-undo.

            /* Run the appropriate internal procedure for the OS. */
            run Spark/Diagnostic/Util/GetPID persistent set hProc.
            if opsys eq "win32" then
                run GetCurrentProcessId in hProc ( output iAgentID ).
            else
                run GetPID in hProc ( output iAgentID ).

            finally:
                delete object hProc no-error.
            end finally.
        end. /* Unknown PID Value */

        /* Don't return an unknown PID. */
        if iAgentID eq ? then assign iAgentID = 0.

        return integer(iAgentID).

        finally:
            delete object oRequestInfo no-error.
        end finally.
    end method. /* GetAgentID */


    method private integer GetSessionID ( ):
        define variable oRequestInfo as OERequestInfo no-undo.
        define variable iSessionID   as integer       no-undo.

        assign oRequestInfo = this-object:GetRequestInfo().
        if valid-object(oRequestInfo) then
            assign iSessionID = oRequestInfo:SessionId.

        /* Don't return an unknown PID. */
        if iSessionID eq ? then assign iSessionID = 0.

        return iSessionID.

        finally:
            delete object oRequestInfo no-error.
        end finally.
    end method. /* GetSessionID */


    /***** Public Methods *****/


    method public logical StartProfiler ( input pcTrackBy as character ):
        /* Start the profiler with any config-set filtering. */
        if (oConfig:ProfilerFilter gt "") eq true then
            return this-object:StartProfiler(pcTrackBy, oConfig:ProfilerFilter).
        else
            return this-object:StartProfiler(pcTrackBy, "*"). /* No filter. */
    end method. /* StartProfiler */


    method public logical StartProfiler ( input pcTrackBy as character,
                                          input pcFilter  as character ):
        /**
         * Method is meant to allow starting of the ABL profiler via either an
         * MSAS session startup or activate procedure, while the writing of the
         * report can be done within a session shutdown or deactivate procedure.
         * Note that the profiler can run either across an entire session or on
         * each request to a session, but not both.
         */

        /* Check if profiling is allowed, based on flags and scheduled time. */
        if not oConfig:IsProfilerEnabled("StartProfiler") then return false.
        if not oConfig:OnValidSchedule() then return false.

        /* Ignore start of profiler if not configured to track by stated type. */
        if pcTrackBy ne oConfig:ProfilerTrackBy then return false.
 
        define variable lFilterMatch as logical   no-undo initial false.
        define variable cBasePath    as character no-undo.
        define variable cOutPath     as character no-undo initial "".
        define variable cProcedure   as character no-undo.

        /* Get the current procedure, if available. */
        assign cProcedure = this-object:GetProcedureName().

        if (oConfig:PollingIgnoreList gt "") eq true then do:
            /* Do not proceed if current request procedure is on the ignore list. */
            if this-object:InMatchList(cProcedure, oConfig:PollingIgnoreList) then do:
                oMetricsLogger:Trace(substitute("[Profiler] Procedure Ignored: &1", cProcedure)).
                return false. /* Leave on first match of ignore list. */
            end. /* ignored */
        end. /* has ignore list */

        /* Create base path for output and create any needed directories. */
        assign cBasePath = substitute("&1/metrics/ProfilerData/&2",
                                      this-object:TemporaryDir, this-object:GetAgentID()).
        os-create-dir value(cBasePath).

        /* Always prepare to output if tracking by session. */
        if oConfig:ProfilerTrackBy eq "session" then do:
            /* Determine correct output location for this profiler log. */
            assign cOutPath = substitute("&1/&2.&3_A&4.prof",
                                         cBasePath, iso-date(today), mtime, this-object:GetAgentID()).
        end. /* Track By Session */
        else do:
            /* Filter should not be blank, so fill with wildcard at least. */
            if (pcFilter gt "") ne true then assign pcFilter = "*".

            /* Check if requested procedure matches in the filter whitelist. */
            if this-object:InMatchList(cProcedure, pcFilter) then do:
                /* Obtain the request information and set/increment special values. */
                assign this-object:RequestCount = this-object:RequestCount + 1.
                assign this-object:RequestStart = now.
                assign cOutPath = substitute("&1/&2.&3_R&4_A&5_S&6.prof",
                                             cBasePath, iso-date(today), mtime, this-object:RequestCount,
                                             this-object:GetAgentID(), this-object:GetSessionID()).
            end. /* matches */
        end. /* Track By Request */

        if (cOutPath gt "") eq true then do:
            assign /* Note: Order matters here, do not rearrange! */
                profiler:enabled      = true
                profiler:profiling    = true
                profiler:file-name    = cOutPath
                profiler:description  = "Profiler Output"
                profiler:trace-filter = "*":u
                profiler:tracing      = "":u
                profiler:coverage     = true
                profiler:statistics   = true
                .
            return true.
        end.

        return false. /* No filter matched for profiling. */

        catch err as Progress.Lang.Error:
            /* Should fail silently, while delivering errors to the standard local. */
            oMetricsLogger:Error(substitute("Error starting profiler: &1", err:GetMessage(1))).
            return false.
        end catch.
    end method. /* StartProfiler */


    method public logical WriteProfiler ( input pcTrackBy as character ):
        /* Start the profiler with any config-set filtering. */
        if oConfig:ProfilerThreshold gt 0 then
            return this-object:WriteProfiler(pcTrackBy, oConfig:ProfilerThreshold).
        else
            return this-object:WriteProfiler(pcTrackBy, 0). /* No threshold. */
    end method. /* StartProfiler */


    method public logical WriteProfiler ( input pcTrackBy       as character,
                                          input piExecThreshold as integer ):
        /**
         * Method is created as static to allow profiler output to be generated at
         * any time in the request lifecycle without dependency on a class instance.
         * Output beyond the profiler data itself should be performed via the new
         * LogWriter feature to place information/errors into a dedicated log file.
         * This allows for additional context about a request to be logged without
         * generating a standalone file, whether the profiler output has been made
         * available or not (eg. excution time may always be reported).
         */

        /* Ignore ending of profiler if not configured to track by stated type. */
        if pcTrackBy ne oConfig:ProfilerTrackBy then return false.

        if not oConfig:IsProfilerEnabled("WriteProfiler") then do:
            /* Even if profiling has been disabled, make sure we turn it off. */
            if profiler:enabled then
                assign
                    profiler:profiling = false
                    profiler:enabled   = false
                    .

            return false.
        end. /* not enabled */

        if profiler:enabled then do:
            /* Always turn off the profiler, if previously enabled. */
            assign
                profiler:profiling = false
                profiler:enabled   = false
                .

            if oConfig:ProfilerTrackBy eq "session" then do:
                oMetricsLogger:Debug(substitute("Write Profiler: A&1 | S&2",
                                                this-object:GetAgentID(),
                                                this-object:GetSessionID())).

                profiler:write-data(). /* Always write profiler data. */
            end. /* ProfilerTrackBy = Session */
            else do:
                /* Determine the time elapsed for this request. */
                define variable iExecTime as integer no-undo initial 0.
                if this-object:RequestStart ne ? and this-object:RequestStart lt now then
                    assign iExecTime = interval(now, this-object:RequestStart, "milliseconds" ).

                /* Only write the data out if execution time exceeds threshold. */
                if piExecThreshold eq ? or piExecThreshold lt 0 then assign piExecThreshold = 0.
                if iExecTime gt piExecThreshold then do:
                    /* Execution time threshold met, output the profiler data. */
                    oMetricsLogger:Debug(substitute("Write Profiler: &1 | &2ms | R&3 | A&4 | S&5",
                                                    this-object:GetProcedureName(), iExecTime, this-object:RequestCount,
                                                    this-object:GetAgentID(), this-object:GetSessionID())).

                    profiler:write-data(). /* Write profiler data when over threshold. */
                end. /* iExecTime gt piExecThreshold */
                else
                    oMetricsLogger:Trace(substitute("&1 | &2ms | -Threshold Not Met; No Profiler Output-",
                                                    this-object:GetProcedureName(), iExecTime)).                
            end. /* ProfilerTrackBy = Request */

            return true.
        end. /* profiler:enabled */
        else
            oMetricsLogger:Trace(substitute("&1 | &2ms | -Profiler Not Enabled-",
                                            this-object:GetProcedureName(), iExecTime)).

        return false. /* Profiler not enabled. */

        catch err as Progress.Lang.Error:
            /* Should fail silently, while delivering errors to the standard local. */
            oMetricsLogger:Error(substitute("Error writing profiler: &1", err:GetMessage(1))).
            return false.
        end catch.
    end method. /* WriteProfiler */


    method public logical StartTrackingObjects ( ):
        /**
         * Send the request to obtain the report by JMX/OEM.
         */

        /* Check if object reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreObjectsEnabled("StartTrackingObjects") then return false.
        if not oConfig:OnValidSchedule() then return false.

        return this-object:StartTrackingObjects(this-object:GetAgentID(), this-object:GetProcedureName()).
    end method. /* StartTrackingObjects */


    method public logical StartTrackingObjects ( input piAgentID   as integer,
                                                 input pcProcedure as character ):
        /**
         * Request the current agent start tracking ABLObjects. This
         * should first check a local flag to determine if tracking
         * has already been started, as a request via OEJMX can be
         * expensive, and the data is impossible to share across
         * session memory.
         */

        /* Check if object reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreObjectsEnabled("StartTrackingObjects") then return false.
        if not oConfig:OnValidSchedule() then return false.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        define variable lIsTracking as logical   no-undo initial false.
        define variable cTrackFlag  as character no-undo.

        if (oConfig:PollingIgnoreList gt "") eq true then do:
            /* Do not proceed if current request procedure is on the ignore list. */
            if this-object:InMatchList(pcProcedure, oConfig:PollingIgnoreList) then do:
                oMetricsLogger:Trace(substitute("[Tracking] Procedure Ignored: &1", pcProcedure)).
                return false. /* Leave on first match of ignore list. */
            end. /* ignored */
        end. /* has ignore list */

        /* Avoid making the call to the agent if we have previously marked this agent as tracking objects. */
        assign cTrackFlag = oConfig:GetTrackingFlag(piAgentID).
        file-info:file-name = cTrackFlag.
        if file-info:full-pathname ne ? then do:
            assign lIsTracking = true. /* Flag exists, assume tracking is enabled. */
            oMetricsLogger:Debug(substitute("Tracking Agent #&1: &2", piAgentID, lIsTracking)).
        end. /* file exists */

        if not lIsTracking then do:
            /* Turn on tracking if not already enabled, and record the latest result. */
            assign lIsTracking = oRemoteMetrics:TrackABLObjects(piAgentID, true).

            /* Remember whether objects are being tracked for this agent. */
            if lIsTracking then do:
                output to value(cTrackFlag).
                /* No output, just touch file. */
                output close.
            end. /* Tracking */

            /* Also begin tracking requests by making an initial call to this endpoint. */
            if oConfig:AreRequestsEnabled("StartTrackingObjects") then
                this-object:GetRequestMetrics(piAgentID).
        end. /* not lIsTracking */

        return lIsTracking.
    end method. /* StartTrackingObjects */


    method public logical StopTrackingObjects ( ):
        /* Run the request using the current agent ID. */
        return this-object:StopTrackingObjects(this-object:GetAgentID()).
    end method. /* StopTrackingObjects */


    method public logical StopTrackingObjects ( input piAgentID as integer ):
        /**
         * Request the current agent stop tracking ABLObjects.
         */

        if not oConfig:AreObjectsEnabled("StopTrackingObjects") then return false.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        /* Remove the agent flag when tracking is stopped. */
        define variable cTrackFlag as character no-undo.
        assign cTrackFlag = oConfig:GetTrackingFlag(piAgentID).
        file-info:file-name = cTrackFlag.
        if file-info:full-pathname ne ? then
            os-delete value(file-info:full-pathname).

        /* Just immediately disable the object tracking for this agent. */
        return oRemoteMetrics:TrackABLObjects(this-object:GetAgentID(), false).
    end method. /* StopTrackingObjects */


    method public logical GetABLObjects ( ):
        /**
         * Return the ABLObjects report from the current agent.
         */

        /* Check if object reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreObjectsEnabled("GetABLObjects") then return false.
        if not oConfig:OnValidSchedule() then return false.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        define variable iAgentID   as integer    no-undo.
        define variable iCount     as integer    no-undo.
        define variable cProcedure as character  no-undo.
        define variable cSessionID as character  no-undo extent.
        define variable lReturn    as logical    no-undo initial false.
        define variable oObjReport as JsonObject no-undo.

        assign cProcedure = this-object:GetProcedureName().
        if (oConfig:PollingIgnoreList gt "") eq true then do:
            /* Do not proceed if current request procedure is on the ignore list. */
            if this-object:InMatchList(cProcedure, oConfig:PollingIgnoreList) then do:
                oMetricsLogger:Trace(substitute("[Objects] Procedure Ignored: &1", cProcedure)).
                return false. /* Leave on first match of ignore list. */
            end. /* ignored */
        end. /* has ignore list */

        assign iAgentID = this-object:GetAgentID(). /* Obtain the current AgentID. */

        /* Request the current ABLObjects report for this agent. */
        if oRemoteMetrics:FilterABLObjectReport(input  iAgentID,
                                                input  oConfig:ClassesExcluded,
                                                output oObjReport) then do:
            /* Output a file for each session in the report. */
            assign cSessionID = oObjReport:GetNames().
            do iCount = 1 to extent(cSessionID):
                /* Output the report to a known location on disk for review/archival. */
                assign lReturn = oObjReport:GetJsonArray(cSessionID[iCount])
                                           :WriteFile(this-object:GetObjectsPath(iAgentID,
                                                                                 integer(cSessionID[iCount])),
                                                                                 true).
            end. /* do iCount */
        end. /* ParseABLObjectReport */

        return lReturn.

        finally:
            delete object oObjReport no-error.
        end finally.
    end method. /* GetABLObjects */


    method public logical TrackAllAgents ( input plEnable as logical ):
        /**
         * Obtain a list of all available agents and make a request to each
         * to begin tracking ABLObjects. This can be time-consuming if there
         * are many agents configured per PAS instance.
         */

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        define variable oAgent   as JsonObject no-undo.
        define variable cAgentID as character  no-undo.
        define variable iCount   as integer    no-undo.
        define variable lSuccess as logical    no-undo initial false.

        /* Get the agents if object is not present. */
        if not valid-object(RemoteMetrics:AgentList) then oRemoteMetrics:GetAgents().

        /* Make request to all agents of this ABLApp. */
        do iCount = 1 to RemoteMetrics:AgentList:Length:
            /* Set request with PAS instance name and specific Agent ID. */
            assign oAgent = RemoteMetrics:AgentList:GetJsonObject(iCount).
            if valid-object(oAgent) and oAgent:Has("pid") then do:
                /* Set the tracking option for this agent. */
                assign cAgentID = oAgent:GetCharacter("pid").
                if oRemoteMetrics:TrackABLObjects(integer(cAgentID), plEnable) then
                    assign lSuccess = true.
            end. /* has agentId */
        end. /* do iCount */

        return lSuccess.
    end method. /* TrackAllAgents */


    method public logical GetAllABLObjectsReport ( ):
        /**
         * Obtain a list of all available agents and make a request to each
         * to return the current ABLObjectsReport. This can be time-consuming
         * if there are many agents configured per PAS instance.
         */

        define variable oObjReport as JsonObject no-undo.
        define variable oAgent     as JsonObject no-undo.
        define variable cAgentID   as character  no-undo.
        define variable cSessionID as character  no-undo extent.
        define variable iCount     as integer    no-undo.
        define variable lReturn    as logical    no-undo initial false.

        /* Check if object reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreObjectsEnabled("GetAllABLObjectsReport") then return false.
        if not oConfig:OnValidSchedule() then return false.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        /* Get the agents if object is not present. */
        if not valid-object(RemoteMetrics:AgentList) then oRemoteMetrics:GetAgents().

        /* Make request to all agents of this ABLApp. */
        do iCount = 1 to RemoteMetrics:AgentList:Length:
            /* Set request with PAS instance name and specific Agent ID. */
            assign oAgent = RemoteMetrics:AgentList:GetJsonObject(iCount).
            if oAgent:Has("pid") then
            do on error undo, throw:
                /* Extract the current agent for examination. */
                assign cAgentID = oAgent:GetCharacter("pid").

                /* Request the ABL objects for this specific agent. */
                if oRemoteMetrics:FilterABLObjectReport(input  integer(cAgentID),
                                                        input  oConfig:ClassesExcluded,
                                                        output oObjReport) then do:
                    /* Output a file for each session in the report. */
                    assign cSessionID = oObjReport:GetNames().
                    do iCount = 1 to extent(cSessionID):
                        /* Output the report to a known location on disk for review/archival. */
                        assign lReturn = oObjReport:GetJsonArray(cSessionID[iCount])
                                                   :WriteFile(this-object:GetObjectsPath(integer(cAgentID),
                                                                                         integer(cSessionID[iCount])),
                                                                                         true).
                    end. /* do iCount */
                end. /* ParseABLObjectReport */
            end. /* has agentId */
        end. /* do iCount */

        return lReturn.

        finally:
            delete object oObjReport no-error.
        end finally.
    end method. /* GetAllABLObjectsReport */


    method public logical GetSessionABLObjects ( ):
        /* When no parameters passed, use the current agent/session ID's. */
        return this-object:GetSessionABLObjects(this-object:GetAgentID(), this-object:GetSessionID()).
    end method. /* GetSessionABLObjects */


    method public logical GetSessionABLObjects ( input piAgentID   as integer,
                                                 input piSessionID as integer ):
        /**
         * Return the available ABLObjectsReport for the
         * agent and session of the current request.
         */

        define variable oObjReport as JsonArray no-undo.
        define variable cProcedure as character no-undo.
        define variable lReturn    as logical   no-undo initial false.

        /* Check if object reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreObjectsEnabled("GetAllABLObjectsReport") then return false.
        if not oConfig:OnValidSchedule() then return false.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        assign cProcedure = this-object:GetProcedureName().
        if (oConfig:PollingIgnoreList gt "") eq true then do:
            /* Do not proceed if current request procedure is on the ignore list. */
            if this-object:InMatchList(cProcedure, oConfig:PollingIgnoreList) then do:
                oMetricsLogger:Trace(substitute("[Objects] Procedure Ignored: &1", cProcedure)).
                return false. /* Leave on first match of ignore list. */
            end. /* ignored */
        end. /* has ignore list */

        if piAgentID gt 0 and piSessionID gt 0 then do:
            /* Request the ABL objects for this specific agent and session. */
            if oRemoteMetrics:FilterSessionABLObjectReport(input  piAgentID,
                                                           input  piSessionID,
                                                           input  oConfig:ClassesExcluded,
                                                           output oObjReport) then
                /* Output the report to a known location on disk for review/archival. */
                assign lReturn = oObjReport:WriteFile(this-object:GetObjectsPath(piAgentID, piSessionID), true).
        end. /* Has Agent/Session */

        return lReturn.

        finally:
            delete object oObjReport no-error.
        end finally.
    end method. /* GetSessionABLObjects */


    method public void GetRequestMetrics ( input piAgentID as integer ):
        /**
         * Send the request to obtain request metrics by JMX/OEM.
         */

        define variable oRequests as JsonArray.

        /* Check if general reporting is allowed, based on flags and scheduled time. */
        if not oConfig:AreRequestsEnabled("GetRequestMetrics") then return.
        if not oConfig:OnValidSchedule() then return.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        /* Obtain the current list of sessions for this agent. */
        oRemoteMetrics:GetRequestMetrics(input piAgentID, output oRequests).

        /* Output the report to a known location on disk for review/archival. */
        if valid-object(oRequests) and oRequests:Length gt 0 then
            oRequests:WriteFile(this-object:GetRequestPath(piAgentID), true).

        finally:
            delete object oRequests no-error.
        end finally.
    end method. /* GetRequestMetrics */


    method public void GetSessionMetrics ( input piAgentID as integer ):
        /**
         * Send the request to obtain session metrics by JMX/OEM.
         */

        define variable oSessions as JsonArray.

        /* Check if session metrics are allowed, based on flags and scheduled time. */
        if not oConfig:IsMemoryEnabled("GetSessionMetrics") then return.
        if not oConfig:OnValidSchedule() then return.

        /* Update username/password for OEM, if enabled. */
        oConfig:UpdateCredentialsOEM(oRemoteMetrics).

        /* Obtain the current list of sessions for this agent. */
        oRemoteMetrics:GetSessions(input piAgentID, output oSessions).

        /* Output the report to a known location on disk for review/archival. */
        if valid-object(oSessions) and oSessions:Length gt 0 then
            oSessions:WriteFile(this-object:GetSessionPath(piAgentID), true).

        finally:
            delete object oSessions no-error.
        end finally.
    end method. /* GetSessionMetrics */


    method public void PrepareSessionReports ( ):
        /**
         * Determine if the timing is right to output an ABLObject report
         * for the current agent/session based on reporting interval. Since
         * this class is started as a static instance, it should be tied to
         * one and ONLY one session for any given agent. Therefore, we should
         * be able to just check a single value in this class instance to know
         * when we last output data, and whether it is time to do so again.
         */

        /* Check if general reporting is allowed, based on scheduled time. */
        if not oConfig:OnValidSchedule() then return.

        define variable dNextReportOutput as datetime no-undo initial ?.
        if oConfig:OutputInterval gt 0 then do:
            /* Check when reports were last output. */
            if dLastReportOutput eq ? then do:
                assign
                    dLastReportOutput = now /* Begin the next reporting interval as of right now. */
                    dNextReportOutput = add-interval(now, oConfig:OutputInterval, "milliseconds")
                    .
            end. /* No Previous Interval Recorded */
            else
                assign dNextReportOutput = add-interval(dLastReportOutput,
                                                        oConfig:OutputInterval,
                                                        "milliseconds").
        end. /* oConfig:OutputInterval gt 0 */
        else
            assign dNextReportOutput = now. /* Prepare reports immediately. */

        /* Request report output if current time is equal/greater than the next expected interval. */
        if now ge dNextReportOutput then do:
            /* Immediately update the timestamp to avoid this session requesting the report again. */
            assign dLastReportOutput = now.

            oMetricsLogger:Debug(substitute("Requesting reports for Agent '&1', Session '&2'.",
                                            this-object:GetAgentID(), this-object:GetSessionID())).
            this-object:PrepareSessionReports(this-object:GetAgentID(), this-object:GetSessionID()).
        end. /* Do Output */
        else
            oMetricsLogger:Debug(substitute("Time Until Next Report Interval: &1s",
                                            interval(dNextReportOutput, now, "seconds"))).

        catch err as Progress.Lang.Error:
            oMetricsLogger:Error(substitute("Unable to check last report output for Agent '&1', Session '&2': &3",
                                            this-object:GetAgentID(), this-object:GetSessionID(), err:GetMessage(1))).
            undo, throw err.
        end catch.
    end method. /* PrepareSessionReports */


    method public void PrepareSessionReports ( input piAgentID   as integer,
                                               input piSessionID as integer ):
        if piAgentID le 0 or piAgentID eq ? then return.
        if piSessionID le 0 or piSessionID eq ? then return.

        /**
         * Send the request to obtain the report by JMX/OEM.
         */
        oMetricsLogger:Debug(substitute("Preparing reports for Agent '&1', Session '&2'",
                                        piAgentID, piSessionID)).

        /* Check if reporting is allowed, based scheduled time. */
        if not oConfig:OnValidSchedule() then return.

        /* Run the following reports for the given agent/session. */
        this-object:OutputTime = now. /* Synchronize output time. */
        oMetricsLogger:Info(substitute("Running reports for Agent '&1', Session '&2' at &3",
                                       piAgentID, piSessionID, this-object:OutputTime)).

        if oConfig:AreObjectsEnabled("PrepareSessionABLObjectReport") then
            this-object:GetSessionABLObjects(piAgentID, piSessionID). /* ABLObjects Report */

        if oConfig:IsMemoryEnabled("PrepareSessionABLObjectReport") then
            this-object:GetSessionMetrics(piAgentID). /* Session Metrics, eg. Memory */

        if oConfig:AreRequestsEnabled("PrepareSessionABLObjectReport") then
            this-object:GetRequestMetrics(piAgentID). /* Last 1000 Requests */

        this-object:OutputTime = ?. /* Reset output timestamp. */

        catch err as Progress.Lang.Error:
            oMetricsLogger:Error(substitute("Unable to prepare reports for Agent '&1', Session '&2': &3",
                                            piAgentID, piSessionID, err:GetMessage(1))).
            undo, throw err.
        end catch.
    end method. /* PrepareSessionReports */

end class.