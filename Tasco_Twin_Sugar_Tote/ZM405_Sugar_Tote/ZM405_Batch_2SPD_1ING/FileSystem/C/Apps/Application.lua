--[[
*******************************************************************************

Filename:      Application.lua
Version:       1.0.1.0
Firmware:      2.2.0.10
Date:          2016-03-01
Customer:      Avery Weigh-Tronix
Description:
    This is a two speed one ingredient batching application that shows a bar graph on the Segment display

*******************************************************************************
]]

awtx.display.writeLine("BAT 21",3000)


awtxReq = {}   --create the awtxReq namespace

require("awtxReqConstants")
require("awtxReqVariables")
require("awtxReqDisplayMessages")


--Global Memory Sentinel ... Define this in your app to a different value to clear
-- the Variable table out.
MEMORYSENTINEL = "A4_120001032016"         -- APP_Time_Day_Month_Year
MemorySentinel = awtxReq.variables.SavedVariable('MemorySentinel', "0", true)
-- if the memory sentinel has changed clear out the variable tables.
if MemorySentinel.value ~= MEMORYSENTINEL then
    -- Clears everything
    awtx.variables.clearTable("tblAccum")
    awtx.variables.clearTable("tblAccumConfig")
    awtx.variables.clearTable("tblTare")
    awtx.variables.clearTable("tblTareConfig")
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

saveThruPowerDown = {} -- Table that holds target weight and name through powerdown
saveThruPowerDown.target1 = awtxReq.variables.SavedVariable('target1',0, true) -- Sets target weight index in the table
saveThruPowerDown.name1 = awtxReq.variables.SavedVariable('name1',"",true) -- Sets name index in the table
saveThruPowerDown.cutoff1 = awtxReq.variables.SavedVariable('cutoff1',0,true)
target1 = saveThruPowerDown.target1.value
cutoff1 = saveThruPowerDown.cutoff1.value
actual1 = 0 

date = os.date("%m/%d/%Y") -- Gets todays date from the system
time = os.date("%I:%M") -- Gets the current time from the system
slowTarget1 = target1 -- Entered target weight that needs to be met
fastTarget1 = target1 * cutoff1 -- Calculated target that needs to be met for fast valve to close
output1 = 1 -- This is the output that corresponds to the fast flowing valve
output2 = 2 -- This is the output that corresponds to the slow flowing valve
running = false -- This variable is used to determine if we want the system to be running or not
doPrint = true -- This variable is used to prevent the system from printing when the stop key is pressed

controls = {} -- Creates the controls table

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
createControls() -- Creates controls on start up
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
function awtx.keypad.KEY_TARGET_DOWN()
  awtx.display.setMode(awtx.display.MODE_USER ) -- Sets display to user mode
  tmpTarget1 = saveThruPowerDown.target1.value -- sets the last entered target weight value to a temporary variable
  tmpTarget1, isEnterKey = awtx.keypad.enterWeightWithUnits(tmpTarget1, 0, wt.curCapacity, varUnitStr, 0, -1, 1,"Enter","Target") -- prompts user for target weight value
   
  if (isEnterKey) then
    saveThruPowerDown.target1.value = tmpTarget1 -- saves the new entered value 
    target1 = saveThruPowerDown.target1.value -- saves the new entered value to the target1 variable to be used my the setpoint configuration
    
    slowTarget1 = target1
    actual1 = 0
  else
    awtx.display.writeLine("Abort",500)
    awtx.display.setMode(awtx.display.MODE_SCALE) -- sets display to scale mode
    return
  end
  
    tmpCutoff1 = saveThruPowerDown.cutoff1.value * 100
    tmpCutoff1, isEnterKey1 = awtx.keypad.enterInteger(tmpCutoff1,1,100,-1,"Enter","% Stop")
    
  if (isEnterKey1) then
    saveThruPowerDown.cutoff1.value = tmpCutoff1 / 100
    cutoff1 = saveThruPowerDown.cutoff1.value
  else 
    awtx.display.writeLine("Abort",500)
    awtx.display.setMode(awtx.display.MODE_SCALE)
    return
  end
  
  tmpName1 = saveThruPowerDown.name1.value -- sets the last entered name to a temporary variable
  tmpName1, isEnterKey = awtx.keypad.enterString(tmpName1,4,-1,"Name","Enter") -- prompts the user for a name
  
  if isEnterKey then
    saveThruPowerDown.name1.value = tmpName1 -- saves the new entered name
  else
    awtx.display.writeLine("Abort",500)
    awtx.display.setMode(awtx.display.MODE_SCALE)
    return
  end
  
  fastTarget1 = slowTarget1 * cutoff1
  awtx.display.setMode(awtx.display.MODE_SCALE)
end

--[[
Description:
  This function will get the current state of the setpoint
  if it is finished it will obtain the current weight
  then print the results.
  
Parameters:
  param[in]   number - The setpoint output that is being turned on/off
  param[in]   state - The current state of the setpoint either on or off (true/false)
  
Returns:
  None
]]--
function finished(number,state)
  if (not state and doPrint) then
    tmpStable, actual1 = waitForStability()
    doPrint = false
    running = false
    awtx.weight.graphEnable(1,0) -- disables the graph
    --controls.graph:setVisible(false) -- Hides the bar graph in the dot matrix
    awtx.display.setMode(awtx.display.MODE_USER)
    awtx.display.writeLine("Done",500)
    awtx.display.setMode(awtx.display.MODE_SCALE)
    
    --clear the tare since the batch is done, this will show the full batch
    --weight on the display a.k.a Gross
    --awtx.weight.requestTareClear(1)
    
    awtx.setpoint.activate(4)
    setPrintTokens()
    awtx.printer.PrintFmt(1)
  end
end

function Reseting(number,state)
  
  if (not state) then
    
    awtx.weight.requestTareClear(1)
    
  end

end

  

--[[
Description:
  This function registers the setpoint function that is called when the setpoint changes states
  
Parameters:
  None
  
Returns:
  None
]]--
function onStart()
  
  awtx.setpoint.registerOutputEvent(output2,finished)
  awtx.setpoint.registerOutputEvent(4,Reseting)
    
  end

--[[
Description:
  This function will turn the first ingredient on when the start key is pressed down.
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_START_DOWN()
  wt = awtx.weight.getCurrent(1)
  varCurrentGross=wt.gross
  
  -- Added by Matt Burkett 08/17/16  Added 2nd check to prevent a start on weight over 100lbs per customer request.
  --  Current code now will now allow start on either below zero weight or weight above 100lbs.
  
  if varCurrentGross<0 or varCurrentGross > 100 then
    awtxReq.display.displayCant()
    awtx.display.setMode(awtx.display.MODE_SCALE)
  else
    
    if (target1 > 0 ) then
      if (running == false) then
        
        awtx.display.setMode(awtx.display.MODE_SCALE)
        doPrint = true
        running = true
        awtx.weight.requestTare(1)
        awtx.weight.graphEnable(1,2) -- Enables the bar graph
        awtx.weight.setBar(1,1,0,target1) -- sets the bar graphs max value
        
        -- Added by Matt Burkett 08/17/2016 to tell PLC batch start was called.
        awtx.setpoint.outputSet(3)
        
        awtx.os.sleep(1000)
        awtx.setpoint.outputSet(output1)
        awtx.setpoint.outputSet(output2)
      end
    else
      awtx.display.setMode(awtx.display.MODE_USER)
      awtx.display.writeLine("Invalid",500)
      awtx.display.writeLine("Target",500)
      awtx.display.setMode(awtx.display.MODE_SCALE)
    end
  end
end


--[[
Description:
  This function will turn the outputs off when the stop key is pressed down
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_STOP_DOWN()
  running = false
  doPrint = false
  awtx.weight.graphEnable(1,0) -- disables the graph
  awtx.display.setMode(awtx.display.MODE_SCALE)
  awtx.setpoint.outputClr(output1)
  awtx.setpoint.outputClr(output2)
  awtx.setpoint.outputClr(output3)
end

--[[
Description:
  This function will zero the scale when the zero key is pressed
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_ZERO_DOWN()
  awtx.weight.requestZero()
end

--[[
Description:
  This function will print the current information on the scale when the print key is pressed
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_PRINT_DOWN()
  awtx.weight.getRefreshLastPrint(1)
  awtx.printer.PrintFmt(0)
end

--[[
Description:
  This function will tare the current weight when the tare key is pressed
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_TARE_DOWN()
  awtx.weight.requestTare(1)
end

--[[
Description:
  This function will cycle through the displayable values when the select key is pressed
  
Parameters:
  None
  
Returns:
  None
]]--
function awtx.keypad.KEY_SELECT_DOWN()
  awtx.weight.cycleActiveValue()
end

MAX_LOOP = 100  --100 loops * 0.050 seconds per loop is 5 seconds then exit in waitForStability()

--[[
Description:
  This function waits for the scale to stabilize before getting the weight on the scale.
  And returns after 5 seconds, if motion never stops.
  
Parameters:
  None
  
Returns:
  None
]]--
function waitForStability()
local loop = 0
local tmpStable = true
    wt = awtx.weight.getCurrent(1)
    while wt.motion do        -- waits for a stable weight
        wt = awtx.weight.getCurrent(1)
        awtx.os.systemEvents(50)        -- pause this code for (50) milliseconds and exit function so system code can be checked and run, then return and continue this function
        loop = loop + 1
        if loop > MAX_LOOP then         -- weight has not stablized for 5 seconds so exit loop and return
            tmpStable = false
            break
        end
    end
    return tmpStable, wt.net
end

onStart()
