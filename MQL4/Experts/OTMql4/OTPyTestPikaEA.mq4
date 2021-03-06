// -*-mode: c; c-style: stroustrup; c-basic-offset: 4; coding: utf-8-dos -*-

#property copyright "Copyright 2015 OpenTrading"
#property link      "https://github.com/OpenTrading/"
#property strict

#define INDICATOR_NAME          "PyTestPikaEA"

//? extern int iSEND_PORT=5672;
//? extern int iRECV_PORT=5672;
// can replace this with the IP address of an interface - not lo
extern string uHOST_ADDRESS="127.0.0.1";
extern string uUSERNAME = "guest";
extern string uPASSWORD = "guest";
extern string uEXCHANGE_NAME = "Mt4";
// for testing - in real life we probably want "Mt4" in here for permissions
extern string uVIRTUALHOST = "/";
extern int iTIMER_INTERVAL_SEC = 10;

// disabled if = 0 - callme is not working even though it should be. YMMV.
int iCALLME_TIMEOUT = 0;

extern string uStdOutFile="../../Logs/_test_PyTestPikaEA.txt";

#include <WinUser32.mqh>
/*
This provided the function uBarInfo which puts together the
information you want send to a remote client on every bar.
Change to suit your own needs.
#include <OTMql4/OTBarInfo.mqh>
*/

#include <OTMql4/OTLibLog.mqh>
#include <OTMql4/OTLibStrings.mqh>
#include <OTMql4/OTLibMt4ProcessCmd.mqh>
#include <OTMql4/OTLibProcessCmd.mqh>
#include <OTMql4/OTLibSimpleFormatCmd.mqh>
#include <OTMql4/OTLibJsonFormat.mqh>
#include <OTMql4/OTLibPy27.mqh>
#include <OTMql4/OTPyChart.mqh>

int iCONNECTION = -1;
double fPY_PIKA_CONNECTION_USERS = 0.0;

int iACCNUM;

int iTICK=0;
int iBAR=1;

string uOTPyPikaProcessCmd(string uCmd) {
    string uRetval;
    uRetval = zOTLibProcessCmd(uCmd);
    // can be "void|" return value
    // empty string means the command was not handled.
    return(uRetval);
}

void vPanic(string uReason) {
    // A panic prints an error message and then aborts
    vError("PANIC: " + uReason);
    MessageBox(uReason, "PANIC!", MB_OK|MB_ICONEXCLAMATION);
    ExpertRemove();
}

/* 
We could call Python from an indictator so we distinguish this
*/
int iIS_EA=1;
// This assumes that the symbol and period are not changed.
string uSYMBOL = Symbol();
int iTIMEFRAME = Period();
double fDebugLevel=0;

string uSafeString(string uSymbol) {
    uSymbol = uStringReplace(uSymbol, "!", "");
    uSymbol = uStringReplace(uSymbol, "#", "");
    uSymbol = uStringReplace(uSymbol, "-", "");
    uSymbol = uStringReplace(uSymbol, ".", "");
    return(uSymbol);
}
string uCHART_ID = uChartName(uSafeString(uSYMBOL), iTIMEFRAME, ChartID(), iIS_EA);

int OnInit() {
    int iRetval;
    string uExchangeName;
    string uArg, uRetval;

    if (GlobalVariableCheck("fPyPikaConnectionUsers") == true) {
        fPY_PIKA_CONNECTION_USERS=GlobalVariableGet("fPyPikaConnectionUsers");
    } else {
        fPY_PIKA_CONNECTION_USERS = 0.0;
    }
    if (fPY_PIKA_CONNECTION_USERS > 0.1) {
        iCONNECTION = MathRound(GlobalVariableGet("fPyPikaConnection"));
        if (iCONNECTION < 1) {
            vError("OnInit: unallocated connection");
            return(-1);
        }
        fPY_PIKA_CONNECTION_USERS += 1.0;
    } else {
        iRetval = iPyInit(uStdOutFile);
        if (iRetval != 0) {
            return(iRetval);
        }
        Print("Called iPyInit successfully");
        
        iACCNUM=AccountNumber();

        uArg="import pika";
        iRetval = iPySafeExec(uArg);
        if (iRetval <= -2) {
            // VERY IMPORTANT: if the ANYTHING fails with SystemError we MUST PANIC
            ExpertRemove();
            return(-2);
        } else if (iRetval <= -1) {
            return(-2);
        } else {
            vDebug("Called " +uArg +" successfully");
        }
        
        vPyExecuteUnicode("from OTMql427 import PikaChart");
        vPyExecuteUnicode("sFoobar = '%s : %s' % (sys.last_type, sys.last_value,)");
        uRetval = uPySafeEval("sFoobar");
        if (StringFind(uRetval, "exceptions", 0) >= 0) {
            uRetval = "ERROR: import PikaChart failed: "  + uRetval;
            vPanic(uRetval);
            return(-3);
        } else {
            uRetval = "import PikaChart succeeded: "  + uRetval;
            vDebug(uRetval);
        }

        // for testing - in real life we probably want the PID in here
        uExchangeName = uEXCHANGE_NAME;
        vPyExecuteUnicode(uCHART_ID+"=PikaChart.PikaChart(" +
                          "'" +uCHART_ID + "', " +
                          "sUsername='" + uUSERNAME + "', " +
                          "sPassword='" + uPASSWORD + "', " +
                          "sExchangeName='" + uExchangeName + "', " +
                          "sVirtualHost='" + uVIRTUALHOST + "', " +
                          "sHostAddress='" + uHOST_ADDRESS + "', " +
                          "iDebugLevel=" + MathRound(fDebugLevel) + ", " +
                          ")");
        vPyExecuteUnicode("sFoobar = '%s : %s' % (sys.last_type, sys.last_value,)");
        
        uRetval = uPySafeEval("sFoobar");
        if (StringFind(uRetval, "exceptions", 0) >= 0) {
            uRetval = "ERROR: PikaChart.PikaChart failed: "  + uRetval;
            vPanic(uRetval);
            return(-3);
        } else if (uRetval != " : ") {
            uRetval = "PikaChart.PikaChart errored: "  + uRetval;
            vWarn(uRetval);
        }
        Comment(uCHART_ID);
        
        iCONNECTION = iPyEvalInt("id(" +uCHART_ID +".oCreateConnection())");
        // FixMe:! theres no way to no if this errored! No NAN in Mt4
        if (iCONNECTION <= 0) {
            uRetval = "ERROR: oCreateConnection failed: is RabbitMQ running?";
            vPanic(uRetval);
            return(-3);
        } else {
            uRetval = "oCreateConnection() succeeded: "  + iCONNECTION;
            vInfo(uRetval);
        }
        GlobalVariableTemp("fPyPikaConnection");
        GlobalVariableSet("fPyPikaConnection", iCONNECTION);

        if (iCALLME_TIMEOUT > 0) {
            vInfo("INFO: starting CallmeServer - this make take a while");
            uRetval = uPySafeEval(uCHART_ID+".eStartCallmeServer()");
            if (StringFind(uRetval, "ERROR:", 0) >= 0) {
                uRetval = "WARN: zStartCallmeServer failed: "  + uRetval;
                vWarn(uRetval);
            } else if (uRetval == "") {
                vInfo("INFO: zStartCallmeServer succeeded");
            } else {
                uRetval = "WARN: eStartCallmeServer returned"  + uRetval;
                vWarn(uRetval);
            }
        }
        
        fPY_PIKA_CONNECTION_USERS = 1.0;
        
    }
    GlobalVariableSet("fPyPikaConnectionUsers", fPY_PIKA_CONNECTION_USERS);
    vDebug("OnInit: fPyPikaConnectionUsers=" + fPY_PIKA_CONNECTION_USERS);

    EventSetTimer(iTIMER_INTERVAL_SEC);
    return (0);
}

string ePyPikaPopQueue(string uChartId) {
    string uInput, uOutput, uInfo;
    
    // FixMe: repeat until empty
    // We may want to loop over zMq4PopQueue to pop many commands
    uInput = uPySafeEval(uCHART_ID+".zMq4PopQueue()");
    if (StringFind(uInput, "ERROR:", 0) >= 0) {
        uInput = "ERROR: zMq4PopQueue failed: "  + uInput;
        vWarn("ePyPikaPopQueue: " +uInput);
        return(uInput);
    }

    // the uInput will be empty if there is nothing to do.
    if (uInput == "") {
        //vTrace("ePyPikaPopQueue: " +uInput);
    } else {
        //vTrace("ePyPikaPopQueue: Processing popped exec message: " + uInput);
        uOutput = uOTPyPikaProcessCmd(uInput);
	if (uOutput == "") {
            // if the retval is "" we messed up - dont return a value
	    uOutput = "UNHANDELED: " +uInput;
            vWarn("ePyPikaPopQueue: " +uOutput);
            return(uOutput);
	}
        if (StringFind(uOutput, "error|", 0) == 0) {
            // can be "error|" return value
	    // This means that there was an error in our uOTPyPikaProcessCmd
            vWarn("ePyPikaPopQueue: PikaProcessCmd returned: " +uOutput);
            return(uOutput);
	    // We can return an error value using the form
	    // "retval|...|error|error string"
	}
	if (StringFind(uInput, "cmd", 0) == 0) {
            // if the command is cmd|  - return a value as a retval|
            // We want the sMark from uInput instead of uTime
            // but we will do than in Python
            uInfo = zOTLibSimpleFormatRetval("retval", uCHART_ID, 0, "0", uOutput);
            eReturnOnSpeaker(uCHART_ID, "retval", uInfo, uInput);
            vDebug("ePyPikaPopQueue: retvaled " +uInfo);
            return("");
        }
        if (StringFind(uOutput, "void|", 0) == 0) {
	    // if the command is void| - dont return a value
	} else {
	    vWarn("ePyPikaPopQueue: unrecognized " +uInput + " -> " +uOutput);
	}
    }
    return("");
}

/*
OnTimer is called every iTIMER_INTERVAL_SEC (10 sec.)
which allows us to use Python to look for Pika inbound messages,
or execute a stack of calls from Python to us in Metatrader.
*/
void OnTimer() {
    string uRetval="";
    string uMessage;
    string uMess, uInfo;
    string uType = "timer";
    string uMark;

    /* timer events can be called before we are ready */
    if (GlobalVariableCheck("fPyPikaConnectionUsers") == false) {
      return;
    }
    iCONNECTION = MathRound(GlobalVariableGet("fPyPikaConnection"));
    if (iCONNECTION < 1) {
        vWarn("OnTimer: unallocated connection");
        return;
    }


    // eHeartBeat first to see if there are any commands
    uRetval = uPySafeEval(uCHART_ID+".eHeartBeat("
                          +IntegerToString(iCALLME_TIMEOUT) +")");
    if (StringFind(uRetval, "ERROR: ", 0) >= 0) {
        uRetval = "ERROR: eHeartBeat failed: "  + uRetval;
        vWarn("OnTimer: " +uRetval);
        return;
    }
    uRetval = ePyPikaPopQueue(uCHART_ID);
    if (uRetval != "") {
        vWarn("OnTimer: " +uRetval);
        // drop through
    }
    
    // FixMe: could use GetTickCount but we may not be logged in
    // but maybe TimeCurrent requires us to be logged in?
    // Add microseconds?
    string uTime = IntegerToString(TimeCurrent());
    
    uInfo = "json|" + jOTTimerInformation();
    uMess  = zOTLibSimpleFormatTimer(uType, uCHART_ID, 0, uTime, uInfo);
    eSendOnSpeaker(uCHART_ID, "timer", uMess);
}

void OnTick() {
    static datetime tNextbartime;
    bool bNewBar=false;
    string uType;
    string uInfo;
    string uMess, uRetval;

    fPY_PIKA_CONNECTION_USERS=GlobalVariableGet("fPyPikaConnectionUsers");
    if (fPY_PIKA_CONNECTION_USERS < 0.5) {
        vWarn("OnTick: no connection users");
        return;
    }
    iCONNECTION = MathRound(GlobalVariableGet("fPyPikaConnection"));
    if (iCONNECTION < 1) {
        vWarn("OnTick: unallocated connection");
        return;
    }

    // FixMe: could use GetTickCount but we may not be logged in
    // but maybe TimeCurrent requires us to be logged in?
    string uTime = IntegerToString(TimeCurrent());
    // same as Time[0]
    datetime tTime=iTime(uSYMBOL, iTIMEFRAME, 0);

    if (tTime != tNextbartime) {
        iBAR += 1; // = Bars - 100
        iTICK = 0;
        tNextbartime = tTime;
	uInfo = "json|" + jOTBarInformation(uSYMBOL, Period(), 0) ;
        uType = "bar";
        uMess  = zOTLibSimpleFormatBar(uType, uCHART_ID, 0, uTime, uInfo);
    } else {
        iTICK += 1;
	uInfo = "json|" + jOTTickInformation(uSYMBOL, Period()) ;
        uType = "tick";
        uMess  = zOTLibSimpleFormatTick(uType, uCHART_ID, 0, uTime, uInfo);
    }
    eSendOnSpeaker(uCHART_ID, uType, uMess);
}

void OnDeinit(const int iReason) {
    //? if (iReason == INIT_FAILED) { return ; }
    EventKillTimer();

    fPY_PIKA_CONNECTION_USERS=GlobalVariableGet("fPyPikaConnectionUsers");
    if (fPY_PIKA_CONNECTION_USERS < 1.5) {
        iCONNECTION = MathRound(GlobalVariableGet("fPyPikaConnection"));
        if (iCONNECTION < 1) {
            vWarn("OnDeinit: unallocated connection");
        } else {
            vInfo("OnDeinit: closing the connection");
            vPyExecuteUnicode(uCHART_ID +".bCloseConnectionSockets()");
        }
        GlobalVariableDel("fPyPikaConnection");

        GlobalVariableDel("fPyPikaConnectionUsers");
        vDebug("OnDeinit: deleted fPyPikaConnectionUsers");
        
        vPyDeInit();
    } else {
        fPY_PIKA_CONNECTION_USERS -= 1.0;
        GlobalVariableSet("fPyPikaConnectionUsers", fPY_PIKA_CONNECTION_USERS);
        vDebug("OnDeinit: decreased, value of fPyPikaConnectionUsers to: " + fPY_PIKA_CONNECTION_USERS);
    }
    
    vDebug("OnDeinit: delete of the chart in Python");
    vPyExecuteUnicode(uCHART_ID +".vRemove()");
    Comment("");

}
