--[[
*******************************************************************************

Filename:      Applicaion.lua
Version:       1.0.0.2
Date:          5/4/2016
Customer:      Amalgamated Sugar
Description:
This lua application file provides batch weighing functionality.

*******************************************************************************
]]
--create the awtxReq namespace
awtxReq = {}

require("awtxReqConstants")
require("awtxReqVariables")

--Global Memory Sentinel ... Define this in your app to a different value to clear
-- the Variable table out.
MEMORYSENTINEL = "A5A520150800" 
MemorySentinel = awtxReq.variables.SavedVariable('MemorySentinel', "0", true)
-- if the memory sentinel has changed clear out the variable tables.
if MemorySentinel.value ~= MEMORYSENTINEL then
  -- Clears everything
  awtx.variables.clearTable()
  MemorySentinel.value = MEMORYSENTINEL
end

system = awtx.hardware.getSystem(1) -- Used to identify current hardware type.
config = awtx.weight.getConfig(1)   -- Used to get current system configuration information.
wt = awtx.weight.getCurrent(1)      -- Used to hold current scale snapshot information.
printTokens = {}

-- Initialize print tokens to access various require file variables
for index = 1, 100 do
  printTokens[index] = {}
  printTokens[index].varName  = ""                  -- Holds a string of the variable name of the indexed token.
  printTokens[index].varLabel = "Invalid"           -- Long form name of the token variable.
  printTokens[index].varType  = awtx.fmtPrint.TYPE_UNDEFINED  -- Identifies type of variable for formatting during print operations.
  printTokens[index].varValue = tmp                 -- Holds the current value of the variable.
  printTokens[index].varFunct = ""                  -- Pointer to function used to set the current variable value.

  awtx.fmtPrint.varSet(index, 0, "Invalid", awtx.fmtPrint.TYPE_INTEGER)
end

require("awtxReqAppMenu")         
require("awtxReqScaleKeys")       
require("awtxReqScaleKeysEvents")
require("awtxReqRpnEntry")
require("ReqSetpoint")
require("ReqPresetTare")

-- AppName is displayed when escaping from password entry and entering a password of '0'
AppName = "GENERAL"

--------------------------------------------------------------------------------------------------
--  Super Menu
--------------------------------------------------------------------------------------------------
-- Top level Menu
TopMenu1 = {text = "Super", key = 1, action = "MENU", variable = "SuperMenu"}
TopMenu2 = {text = "EXIT",  key = 2, action = "FUNC", callThis = supervisor.SupervisorMenuExit} 
TopMenu = {TopMenu1, TopMenu2}

-- These lines are needed to construct the top layer of the Supervisor Menu
-- As more menus are added through require files, this layer will grow to include them.
SuperMenu  = { }
SuperMenu1 = {text = " TotBat  ",  key = 1, action = "MENU", variable = "TareSetupMenu", show = (system.modelStr == "ZM405")}
SuperMenu2 = {text = " BACK  ",  key = 2, action = "MENU", variable = "TopMenu", subMenu = 1} 
SuperMenu  = {SuperMenu1, SuperMenu2}

TareSetupMenu1 = {text = " View ",  key = 1, action = "FUNC", callThis = findTare}
TareSetupMenu2 = {text = " Zero ",  key = 2, action = "FUNC", callThis = printTareList, show = true}
TareSetupMenu3 = {text = " Reset ",  key = 3, action = "FUNC", callThis = tareReset, show = true}
TareSetupMenu4 = {text = " BACK  ",  key = 4, action = "MENU", variable = "SuperMenu", subMenu = 1} 
TareSetupMenu  = {TareSetupMenu1, TareSetupMenu2, TareSetupMenu3, TareSetupMenu4}

-- Need this to turn the table string names into the table addresses 
generalMenu = {
  TopMenu = TopMenu,
  SuperMenu = SuperMenu,
  TareSetupMenu = TareSetupMenu
}


--[[
Description:
  Function override from ReqAppMenu.lua
  This function is called when the Supervisor menu is entered.
Parameters:
  None
  
Returns:
  None
]]--
function appEnterSuperMenu()
  setpoint.disableOutputSetpoints()  -- Disable setpoints before entering supervisor menu.
  supervisor.menuLevel    = TopMenu         -- Set current menu level
  supervisor.menuCircular = generalMenu     -- Set menu address table
end

function resetbatch()
  --choice,isEnterKey = awtx.keypad.selectList("No,Yes",0,-1)
  totalbatch = 0 
  saveThruPowerDown.totalbatch.value = totalbatch
  appExitSuperMenu()
  
end


function appExitSuperMenu()
  -- This function retrieves the updated values from the setpoint configuration table
  --  and updates the current setpoints with the latest information.
  setpoint.enableOutputSetpoints()
end

saveThruPowerDown = {} -- Table that holds target weight and name through powerdown
saveThruPowerDown.target1 = awtxReq.variables.SavedVariable('target1',0, true) -- Sets target weight index in the table
saveThruPowerDown.target2 = awtxReq.variables.SavedVariable('target2',0, true)
saveThruPowerDown.name1 = awtxReq.variables.SavedVariable('name1',"",true) -- Sets name index in the table
saveThruPowerDown.DraftTotal = awtxReq.variables.SavedVariable('DraftTotal',0,true)
saveThruPowerDown.totalbatch = awtxReq.variables.SavedVariable('totalbatch',0,true)
saveThruPowerDown.batch = awtxReq.variables.SavedVariable('batch',0,true)
saveThruPowerDown.batchcount = awtxReq.variables.SavedVariable('batchcount',0,true)

batch = saveThruPowerDown.batch.value
target1 = saveThruPowerDown.target1.value
target2 = saveThruPowerDown.target2.value
--cutoff1 = saveThruPowerDown.cutoff1.value
totalbatch = saveThruPowerDown.totalbatch.value
DraftTotal =  saveThruPowerDown.DraftTotal.value
batchcount = saveThruPowerDown.batchcount.value
actual1 = 0 







date = os.date("%m/%d/%Y") -- Gets todays date from the system
time = os.date("%I:%M") -- Gets the current time from the system
slowTarget1 = target2 -10-- Entered target weight that needs to be met
fastTarget1 = target2  -50-- Calculated target that needs to be met for fast valve to close
output1 = 1 -- This is the output that corresponds to the fast flowing valve
output2 = 2 -- This is the output that corresponds to the slow flowing valve
running = false -- This variable is used to determine if we want the system to be running or not
doPrint = true -- This variable is used to prevent the system from printing when the stop key is pressed
ScaleTarget = target2  -- This variable is temporary and is used for batching temporary values
controls = {} -- Creates the controls table
BeginningWt = 0  -- Store the beginning weight at the start of each draft.
StopPressed = false  -- Track if the stop key is pressed.
BatchComplete = false  -- Track when batch completes
DumpingScale = false


--[[
Description:
  This function creates all the controls that are used in Screen0
  
Parameters:
  None
  
Returns:
  None
]]--
function createControls()
  
  controls.graph = awtx.graphics.graph.new('graph', 0, 0, 0, 1000)
  controls.graph:setLocation(0, 12) -- Sets the location of the bar graph in the dot matrix
  controls.graph:reSize(35, 4) -- Sets the size of the bar graph in the dot matrix
  controls.graph:setLimits(0,target1) -- Sets the max value of the bar graph to the target weight of setpoint 1
  controls.graph:setBasis(1)
  controls.graph:setVisible(true)

  controls.scale = awtx.display.getScaleControl()
  controls.setpoints = awtx.display.getSetpointControl()
end
createControls() -- Creates controls on up
local screen0 = nil
varUnitStr= wt.unitsStr      -- Get the units String
varCurrentGross=wt.gross     -- Get current Gross
varCurrentDiv=wt.curDivision -- Get the division size 

--[[
Description:
  This function opens or shows Screen0
  
Parameters:
  None
  
Returns:
  None
]]--
function enterScreen0() 
  awtx.display.setMode(awtx.display.MODE_USER ) -- Sets display to user mode
  screen0:show()
end

--[[
Description:
  This function creates a new screen called screen0
  
Parameters:
  None
  
Returns:
  None
]]--
function createScreen0()
  -- Create the screen
  screen0 = awtx.graphics.screens.new('screen0')
  screen0:addControl(controls.graph) -- Add graph control to the screen
  screen0:addControl(controls.scale) -- Add scale control the the screen
  screen0:addControl(controls.setpoints) -- Add setpoint control to the screen

end
createScreen0() -- creates Screen0 on start up

--[[
Description:
  This function will grab the time and date and set the print tokens to print
  
Parameters:
  None
  
Returns:
  None
]]--
function setPrintTokens()
  date = os.date("%m/%d/%Y") -- Gets todays date from the system
  time = os.date("%I:%M") -- Gets the current time from the system
  awtx.fmtPrint.varSet(1,time,"Time",awtx.fmtPrint.TYPE_STRING)
  awtx.fmtPrint.varSet(2,date,"Date",awtx.fmtPrint.TYPE_STRING)
  awtx.fmtPrint.varSet(3,saveThruPowerDown.target1.value,"Target 1",awtx.fmtPrint.TYPE_FLOAT)
  awtx.fmtPrint.varSet(4,actual1,"Actual 1",awtx.fmtPrint.TYPE_FLOAT)
  awtx.fmtPrint.varSet(5,saveThruPowerDown.name1.value,"Name",awtx.fmtPrint.TYPE_STRING)
  awtx.fmtPrint.varSet(7,saveThruPowerDown.totalbatch.value,"Total Batch for campaign",awtx.fmtPrint.TYPE_FLOAT)
  awtx.fmtPrint.varSet(8,saveThruPowerDown.batch.value,"Single Batch weight",awtx.fmtPrint.TYPE_FLOAT)
end

--[[
Description:
  This function will prompt the user for the target weight and cutoff percenatge 
  for the fast flowing valve. It also calculates the target weight that needs to be
  reached for the fast flowing valve.
  
Parameters:
  None
  
Returns:
  None
]]--

function awtx.keypad.KEY_START_DOWN ()
  
    SpState = awtx.setpoint.getState(10)
    
    if ( running == false and SpState == 1) then
      
      totalbatch = 0
      DraftTotal = 0
      saveThruPowerDown.totalbatch.value = totalbatch
      running = true
      ScaleTarget = target2  -- Set the amount to fill the scale.
      BatchComplete = false
      
      awtx.setpoint.activate(4)
      awtx.weight.graphEnable(1,2) -- Enables the bar graph
      awtx.weight.setBar(1,1,0,target1) -- sets the bar graphs max value
      controls.graph:setLimits(0,target1) -- Sets the maximum value of the bar graph to be the target value of the first setpoint
      enterScreen0()
      print("Starting Total =",totalbatch)  
      BeginFill()
    
    else
      
      -- Check for E-stop State, need code for this
      
      if (SpState == 1 and DumpingScale == false) then
      
        -- Activate setpoints depending on weight
        wt = awtx.weight.getCurrent(1)
        CurrentWt = wt.gross
        
        if (CurrentWt <= fastTarget1) then
        
          awtx.setpoint.activate(1)
          awtx.setpoint.activate(2)
        
        else 
        
          awtx.setpoint.activate(2)
        
        end
    
        StopPressed = false
      
      elseif (SpState == 1 and DumpingScale == true) then
        
        awtx.setpoint.activate(3)
        StopPressed = false
      
      end
  
    end

end


function awtx.keypad.KEY_TARGET_DOWN()
  awtx.display.setMode(awtx.display.MODE_USER ) -- Sets display to user mode
  tmpTarget1 = saveThruPowerDown.target1.value -- sets the last entered target weight value to a temporary variable
  tmpTarget1, isEnterKey = awtx.keypad.enterWeightWithUnits(tmpTarget1, 0, 300000, varUnitStr, 0, -1, 1,"Enter","Target") -- prompts user for target weight value
  -- Sets display to user mode
  if (isEnterKey) then
    saveThruPowerDown.target1.value = tmpTarget1 -- saves the new entered value 
    target1 = saveThruPowerDown.target1.value -- saves the new entered value to the target1 variable to be used my the setpoint configuration
    --totalbatch = saveThruPowerDown.totalbatch.value
    --slowTarget1 = target1

    --fastTarget1 = target1-50
    actual1 = 0
  else
    awtx.display.writeLine("Abort",500)
    awtx.display.setMode(awtx.display.MODE_SCALE) -- sets display to scale mode
    return
  end

  --cutoff1 = saveThruPowerDown.cutoff1.value
  awtx.display.setMode(awtx.display.MODE_SCALE)
end

--[[
Description:
  This function registers the setpoint function that is called when the setpoint changes states
]]--
function awtxReq.keypad.onSampleKeyDown()
  awtx.display.setMode(awtx.display.MODE_USER ) -- Sets display to user mode
  tmpTarget2 = saveThruPowerDown.target2.value -- sets the last entered target weight value to a temporary variable
  tmpTarget2, isEnterKey = awtx.keypad.enterWeightWithUnits(tmpTarget2, 0, wt.curCapacity, varUnitStr, 0, -1, 1,"Enter","Scale Target") -- prompts user for target weight value

  if (isEnterKey) then
    saveThruPowerDown.target2.value = tmpTarget2 -- saves the new entered value 
    target2 = saveThruPowerDown.target2.value -- saves the new entered value to the target1 variable to be used my the setpoint configuration


  else
    awtx.display.writeLine("Abort",500)
    awtx.display.setMode(awtx.display.MODE_SCALE) -- sets display to scale mode
    return
  end
  awtx.display.setMode(awtx.display.MODE_SCALE)
-- saves
  -- Redefine function to change functionality
end

function onStart()
  
  awtx.fmtPrint.varSet(7, "totalbatch", "Total Batch Weight", awtx.fmtPrint.TYPE_INTEGER_VAR)
  awtx.fmtPrint.varSet(8, "batch", "Batch Weight", awtx.fmtPrint.TYPE_INTEGER_VAR)
  awtx.setpoint.registerOutputEvent(4, onSP4Change)
  awtx.setpoint.registerOutputEvent(2, onSP2Change)
  awtx.setpoint.registerInputEvent(10, onSP10Change)
  timerID1 = awtx.os.createTimer(luaTimerCallback, 1000)

end 

--[[
Description:
  This function will turn the first ingredient on when the start key is pressed down.
  
Parameters:
  None
  
Returns:
  None
]]--
function onSP4Change(number, state)
  
  if (state == true ) then  -- The scale has zero'd
    
    awtx.setpoint.deactivate(3)    -- Shuts down the gate 
    awtx.os.sleep(1000)   -- Wait for a second
    
    wt = awtx.weight.getCurrent(1)    -- Get the current weight
    BeginningWt=wt.gross
    
  
    if (target1 > 0) then
      if (running == true) then
        
        awtx.display.setMode(awtx.display.MODE_SCALE)
        doPrint = false
        DumpingScale = false
        BeginFill()
        
      else
        
        awtx.setpoint.deactivate(4)
        
      end
    else
      awtx.display.setMode(awtx.display.MODE_USER)
      awtx.display.writeLine("Invalid",500)
      awtx.display.writeLine("Target",500)
      awtx.display.setMode(awtx.display.MODE_SCALE)
    end
  end
end

function onSP2Change(number, state)
  
  if (state == false and StopPressed == false) then -- if state = false then the scale has finished filling.
    awtx.os.sleep(1000)
    wt = awtx.weight.getCurrent(1)
    batch=wt.gross - BeginningWt
    totalbatch = totalbatch +  batch
    saveThruPowerDown.batch.value = batch
    saveThruPowerDown.totalbatch.value = totalbatch
    DraftTotal = DraftTotal + 1
    saveThruPowerDown.DraftTotal.value = DraftTotal
    
    DumpingScale = true
    
    awtx.setpoint.deactivate(1)
    awtx.setpoint.deactivate(2)
    awtx.setpoint.activate(3)
    
    print ("Draft #:",DraftTotal)
    print ("Batch Weight: ",batch)
    print("Total Filled:",totalbatch)
    
    if (totalbatch + 50 >= target1) then
      
      awtx.display.setMode(awtx.display.MODE_USER)
      awtx.display.writeLine('Bat Cmp',3000)
      awtx.display.writeLine(totalbatch,10000)
      awtx.display.setMode(awtx.display.MODE_SCALE)
      running = false
      BatchComplete = true
      batchcount = batchcount + 1
      saveThruPowerDown.batchcount.value = batchcount
      
    elseif (totalbatch + ScaleTarget >= target1) then
    
      ScaleTarget = target1 - totalbatch
    
    end
  
  end
  --onSP1Change()
end


function onSP10Change(number, state)
  
  if (state == false) then
    
    ProcessStopEvent()

  end

end

function ProcessStopEvent()
  
  StopPressed = true
  doPrint = false
  awtx.weight.graphEnable(1,0) -- disables the graph
  controls.graph:setVisible(false) -- Hides the bar graph in the dot matrix
  awtx.display.setMode(awtx.display.MODE_SCALE)
  awtx.graphics.clearScreen(0,12,0)
  awtx.setpoint.deactivate(1)
  awtx.setpoint.deactivate(2)
  awtx.setpoint.deactivate(3)
  
end

function awtx.keypad.KEY_STOP_DOWN()
  
  ProcessStopEvent()
  
end


function awtx.keypad.KEY_ZERO_DOWN()
  awtx.weight.requestZero(1)
end

--[[
Description:
  This function will print the current information on the scale when the print key is pressed
  
]]--
function awtx.keypad.KEY_PRINT_DOWN()
  awtx.display.setMode(awtx.display.MODE_USER)
  awtx.display.writeLine("Print",500)

  awtx.display.setMode(awtx.display.MODE_SCALE)
  awtx.weight.getRefreshLastPrint(1)
  awtx.printer.PrintFmt(1)
  print(totalbatch)
end


function awtx.keypad.KEY_TARE_DOWN()
  awtx.weight.requestTare(1)
end


function awtx.keypad.KEY_SELECT_DOWN()
  awtx.weight.cycleActiveValue()
end

--PLC tokens
function luaTimerCallback(timerID1)
  
  print('Batch Completed =',BatchComplete)
  if (BatchComplete == true) then
    Completed = 1
  else
    Completed = 0
  end
  local varSetResult7= awtx.fmtPrint.varSet(7, totalbatch, "Total Batch",TYPE_INTERGER)
  local varSetResult8= awtx.fmtPrint.varSet(8, batch, "Single Batch",TYPE_INTERGER)
  local varSetResult9= awtx.fmtPrint.varSet(9, DraftTotal, "Draft total",TYPE_INTERGER)
  local varSetResult10= awtx.fmtPrint.varSet(10, Completed, "Batch Completed",TYPE_INTERGER)
  local varSetResult11= awtx.fmtPrint.varSet(11, batchcount, "Batch Number",TYPE_INTERGER)
  
end


function awtx.keypad.KEY_F1_DOWN()
  awtx.display.writeLine(totalbatch,5000)
end








function BeginFill()

  fastTarget1 = ScaleTarget - 50
  slowTarget1 = ScaleTarget - 10
  
  awtx.setpoint.activate(1)
  awtx.setpoint.activate(2)

  
end



function BatchComplete()
  
  awtx.display.writeLine('Finish',1000)

end



onStart()


