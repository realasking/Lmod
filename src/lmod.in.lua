#!@path_to_lua@/lua
-- -*- lua -*-

--------------------------------------------------------------------------
-- The main program for Lmod.
-- @script lmod

--------------------------------------------------------------------------
-- Lmod License
--------------------------------------------------------------------------
--
--  Lmod is licensed under the terms of the MIT license reproduced below.
--  This means that Lmod is free software and can be used for both academic
--  and commercial purposes at absolutely no cost.
--
--  ----------------------------------------------------------------------
--
--  Copyright (C) 2008-2016 Robert McLay
--
--  Permission is hereby granted, free of charge, to any person obtaining
--  a copy of this software and associated documentation files (the
--  "Software"), to deal in the Software without restriction, including
--  without limitation the rights to use, copy, modify, merge, publish,
--  distribute, sublicense, and/or sell copies of the Software, and to
--  permit persons to whom the Software is furnished to do so, subject
--  to the following conditions:
--
--  The above copyright notice and this permission notice shall be
--  included in all copies or substantial portions of the Software.
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
--  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
--  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
--  NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
--  BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
--  ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
--  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
--  THE SOFTWARE.
--
--------------------------------------------------------------------------

------------------------------------------------------------------------
-- Use command name to add the command directory to the package.path
------------------------------------------------------------------------

local sys_lua_path = "@sys_lua_path@"
if (sys_lua_path:sub(1,1) == "@") then
   sys_lua_path = package.path
end

local sys_lua_cpath = "@sys_lua_cpath@"
if (sys_lua_cpath:sub(1,1) == "@") then
   sys_lua_cpath = package.cpath
end

package.path   = sys_lua_path
package.cpath  = sys_lua_cpath

local arg_0    = arg[0]
local posix    = require("posix")
local readlink = posix.readlink
local stat     = posix.stat

local st       = stat(arg_0)
while (st.type == "link") do
   arg_0 = readlink(arg_0)
   st    = stat(arg_0)
end

local ia,ja = arg_0:find(".*/")
local LuaCommandName     = false
local LuaCommandName_dir = "./"
if (ia) then
   LuaCommandName_dir = arg_0:sub(1,ja)
   LuaCommandName     = arg_0:sub(ja+1)
end

package.path  = LuaCommandName_dir .. "?.lua;"       ..
                LuaCommandName_dir .. "../tools/?.lua;"  ..
                LuaCommandName_dir .. "../tools/?/init.lua;"  ..
                LuaCommandName_dir .. "../shells/?.lua;" ..
                LuaCommandName_dir .. "?/init.lua;"  ..
                sys_lua_path
package.cpath = LuaCommandName_dir .. "../lib/?.so;"..
                sys_lua_cpath

require("strict")

--------------------------------------------------------------------------
-- Return the path to the Lmod program
function cmdDir()
   return LuaCommandName_dir
end

--------------------------------------------------------------------------
-- Return this program's name.
function cmdName()
   return LuaCommandName
end

require("myGlobals")
require("TermWidth")
require("fileOps")
require("colorize")
require("pager")
require("string_utils")
require("cmdfuncs")
require("utils")

MasterControl       = require("MasterControl")

local Banner        = require("Banner")
local BaseShell     = require("BaseShell")
local BeautifulTbl  = require("BeautifulTbl")
local Exec          = require("Exec")
local FrameStk      = require("FrameStk")

local Options       = require("Options")
local Var           = require("Var")
local Version       = require("Version")
local concatTbl     = table.concat
local cosmic        = require("Cosmic"):singleton()
local dbg           = require("Dbg"):dbg()
local hook          = require("Hook")
local getenv        = os.getenv
local max           = math.max
local timer         = require("Timer"):singleton()
local unpack        = (_VERSION == "Lua 5.1") and unpack or table.unpack

local s_Usage       = false
--------------------------------------------------------------------------
-- Build the lmod usage message and store in *s_Usage*.
function Usage()
   if (s_Usage) then
      return s_Usage
   end
   local website = colorize("red","http://lmod.readthedocs.org/")
   local webBR   = colorize("red","http://lmod.readthedocs.io/en/latest/075_bug_reporting.html")
   local banner  = Banner:singleton()
   local line    = banner:border(2)
   local a = {}
   a[#a+1] = { "module [options] sub-command [args ...]" }
   a[#a+1] = { "" }
   a[#a+1] = { "Help sub-commands:" }
   a[#a+1] = { "------------------" }
   a[#a+1] = { "  help", "",            "prints this message"}
   a[#a+1] = { "  help", "module [...]","print help message from module(s)"}
   a[#a+1] = { "" }
   a[#a+1] = { "Loading/Unloading sub-commands:" }
   a[#a+1] = { "-------------------------------" }
   a[#a+1] = { "  load | add",         "module [...]",  "load module(s)"}
   a[#a+1] = { "  try-load | try-add", "module [...]",  "Add module(s), do not complain if not found"}
   a[#a+1] = { "  del | unload",       "module [...]",  "Remove module(s), do not complain if not found"}
   a[#a+1] = { "  swap | sw | switch", "m1 m2",         "unload m1 and load m2" }
   a[#a+1] = { "  purge",              "",              "unload all modules"}
   a[#a+1] = { "  refresh",            "",              "reload aliases from current list of modules."}
   a[#a+1] = { "  update",             "",              "reload all currently loaded modules."}
   a[#a+1] = { "" }
   a[#a+1] = { "Listing / Searching sub-commands:" }
   a[#a+1] = { "---------------------------------" }
   a[#a+1] = { "  list",         "",             "List loaded modules"}
   a[#a+1] = { "  list",         "s1 s2 ...",    "List loaded modules that match the pattern"}
   a[#a+1] = { "  avail | av",   "",             "List available modules"}
   a[#a+1] = { "  avail | av",   "string",       "List available modules that contain \"string\"."}
   a[#a+1] = { "  spider",       "",             "List all possible modules"}
   a[#a+1] = { "  spider",       "module",       "List all possible version of that module file"}
   a[#a+1] = { "  spider",       "string",       "List all module that contain the \"string\"."}
   a[#a+1] = { "  spider",       "name/version", "Detailed information about that version of the module."}
   a[#a+1] = { "  whatis",       "module",       "Print whatis information about module"}
   a[#a+1] = { "  keyword | key","string",       "Search all name and whatis that contain \"string\"."}
   a[#a+1] = { "" }
   a[#a+1] = { "Searching with Lmod:"}
   a[#a+1] = { "--------------------" }
   a[#a+1] = { "  All searching (spider, list, avail, keyword) support regular expressions:"}
   a[#a+1] = { "" }
   a[#a+1] = { "  spider -r ", "'^p'",  "Finds all the modules that start with `p' or `P'"}
   a[#a+1] = { "  spider -r ", "mpi",   "Finds all modules that have \"mpi\" in their name."}
   a[#a+1] = { "  spider -r ", "'mpi$", "Finds all modules that end with \"mpi\" in their name."}
   a[#a+1] = { "" }
   a[#a+1] = { "Handling a collection of modules:"}
   a[#a+1] = { "--------------------------------" }
   a[#a+1] = { "  save | s",    "",       "Save the current list of modules to a user defined \"default\" collection."}
   a[#a+1] = { "  save | s",    "name",   "Save the current list of modules to \"name\" collection."}
   a[#a+1] = { "  reset",     "",        "The same as \"restore system\""}
   a[#a+1] = { "  restore | r", "",       "Restore modules from the user's \"default\" or system default."}
   a[#a+1] = { "  restore | r", "name",   "Restore modules from \"name\" collection."}
   a[#a+1] = { "  restore",     "system", "Restore module state to system defaults."}
   a[#a+1] = { "  savelist",    "",       "List of saved collections."}
   a[#a+1] = { "  describe | mcc",  "name",  "Describe the contents of a module collection."}
   a[#a+1] = { "" }
   a[#a+1] = { "Deprecated commands:"}
   a[#a+1] = { "--------------------"}
   a[#a+1] = { "  getdefault", "[name]", "load name collection of modules or "..
                                         "user's \"default\" if no name given."}
   a[#a+1] = { "",            "",        "===> Use \"restore\" instead  <===="}
   a[#a+1] = { "  setdefault","[name]",  "Save current list of modules to name if given, "..
                                         "otherwise save as the default list for you the user."}
   a[#a+1] = { "",            "",        "===> Use \"save\" instead. <===="}
   a[#a+1] = { "" }
   a[#a+1] = { "Miscellaneous sub-commands:"}
   a[#a+1] = { "---------------------------"}
   a[#a+1] = { "  show",     "modulefile", "show the commands in the module file."}
   a[#a+1] = { "  use [-a]", "path",       "Prepend or Append path to MODULEPATH."}
   a[#a+1] = { "  unuse",    "path",       "remove path from MODULEPATH."}
   a[#a+1] = { "  tablelist","",           "output list of active modules as a lua table."}
   a[#a+1] = { "" }
   a[#a+1] = { "Important Environment Variables:"}
   a[#a+1] = { "--------------------------------"}
   a[#a+1] = { "  LMOD_COLORIZE", "", "If defined to be \"YES\" then Lmod prints "..
                                      "properties and warning in color."}
   a[#a+1] = { "" }
   a[#a+1] = { line}
   a[#a+1] = { "Lmod Web Sites"}
   a[#a+1] = { "" }
   a[#a+1] = { "  Documentation:    http://lmod.readthedocs.org"}
   a[#a+1] = { "  Github:           https://github.com/TACC/Lmod"}
   a[#a+1] = { "  Sourceforge:      https://lmod.sf.net"}
   a[#a+1] = { "  TACC Homepage:    https://www.tacc.utexas.edu/research-development/tacc-projects/lmod"}
   a[#a+1] = { "" }
   a[#a+1] = { "  To report a bug please read "..webBR }
   a[#a+1] = { line }


   local twidth = TermWidth()
   local bt     = BeautifulTbl:new{tbl=a, column = twidth-1, len = length, wrapped=true}
   s_Usage      = bt:build_tbl()

   return s_Usage
end

--------------------------------------------------------------------------
-- Build the version string.
function version()
   local v = {}
   v[#v + 1] = "\nModules based on Lua: Version " .. Version.name().."\n"
   v[#v + 1] = "    by Robert McLay mclay@tacc.utexas.edu\n\n"
   return concatTbl(v,"")
end

--------------------------------------------------------------------------
-- The main function of Lmod.  The lmod program always starts here.
function main()
   if (LMOD_RTM_TESTING) then
      os.exit(0)
   end

   local epoch        = epoch
   local t1           = epoch()

   local availTbl     = { name = "avail",       checkMPATH = false, cmd = Avail         }
   local gdTbl        = { name = "getDefault",  checkMPATH = false, cmd = GetDefault    }
   local helpTbl      = { name = "help",        checkMPATH = false, cmd = Help          }
   local keywordTbl   = { name = "keyword",     checkMPATH = false, cmd = Keyword       }
   local listTbl      = { name = "list",        checkMPATH = false, cmd = List          }
   local loadTbl      = { name = "load",        checkMPATH = true,  cmd = Load_Usr      }
   local mcTbl        = { name = "describe",    checkMPATH = false, cmd = CollectionLst }
   local purgeTbl     = { name = "purge",       checkMPATH = true,  cmd = Purge         }
   local refreshTbl   = { name = "refresh",     checkMPATH = false, cmd = Refresh       }
   local resetTbl     = { name = "reset",       checkMPATH = true,  cmd = Reset         }
   local restoreTbl   = { name = "restore",     checkMPATH = false, cmd = Restore       }
   local saveTbl      = { name = "save",        checkMPATH = false, cmd = Save          }
   local savelistTbl  = { name = "savelist",    checkMPATH = false, cmd = SaveList      }
   local searchTbl    = { name = "search",      checkMPATH = false, cmd = SearchCmd     }
   local showTbl      = { name = "show",        checkMPATH = false, cmd = Show          }
   local spiderTbl    = { name = "spider",      checkMPATH = true,  cmd = SpiderCmd     }
   local swapTbl      = { name = "swap",        checkMPATH = true,  cmd = Swap          }
   local tblLstTbl    = { name = "tablelist",   checkMPATH = false, cmd = TableList     }
   local tryAddTbl    = { name = "try-add",     checkMPATH = true,  cmd = Load_Try      }
   local unloadTbl    = { name = "unload",      checkMPATH = true,  cmd = UnLoad        }
   local unuseTbl     = { name = "unuse",       checkMPATH = true,  cmd = UnUse         }
   local updateTbl    = { name = "update",      checkMPATH = true,  cmd = Update        }
   local useTbl       = { name = "use",         checkMPATH = true,  cmd = Use           }
   local whatisTbl    = { name = "whatis",      checkMPATH = false, cmd = Whatis        }

   local lmodCmdA = {
      {'^ad'      , loadTbl       },
      {'^ap'      , keywordTbl    },
      {'^av'      , availTbl      },
      {'^del'     , unloadTbl     },
      {'^des'     , mcTbl         },
      {'^dis'     , showTbl       },
      {'^era'     , unloadTbl     },
      {'^gd'      , gdTbl         },
      {'^getd'    , gdTbl         },
      {'^h'       , helpTbl       },
      {'^k'       , keywordTbl    },
      {'^ld'      , savelistTbl   },
      {'^listd'   , savelistTbl   },
      {'^lo'      , loadTbl       },
      {'^l'       , listTbl       },
      {'^mc'      , mcTbl         },
      {'^pu'      , purgeTbl      },
      {'^refr'    , refreshTbl    },
      {'^rel'     , updateTbl     },
      {'^rem'     , unloadTbl     },
      {'^rese'    , resetTbl      },
      {'^rm'      , unloadTbl     },
      {'^r'       , restoreTbl    },
      {'^savel'   , savelistTbl   },
      {'^sd'      , saveTbl       },
      {'^sea'     , searchTbl     },
      {'^setd'    , saveTbl       },
      {'^sh'      , showTbl       },
      {'^sl'      , savelistTbl   },
      {'^sp'      , spiderTbl     },
      {'^sw'      , swapTbl       },
      {'^s'       , saveTbl       },
      {'^table'   , tblLstTbl     },
      {'^try'     , tryAddTbl     },
      {'^unuse$'  , unuseTbl      },
      {'^un'      , unloadTbl     },
      {'^up'      , updateTbl     },
      {'^use$'    , useTbl        },
      {'^w'       , whatisTbl     },
   }

   MCP = MasterControl.build("load")
   mcp = MasterControl.build("load")
   dbg.set_prefix(colorize("red","Lmod"))

   local shellNm = barefilename(arg[1])
   if (BaseShell.isValid(shellNm)) then
      table.remove(arg,1)
   else
      shellNm = "bash"
   end

   local masterTbl = masterTbl()

   -- Push Lmod version into environment
   setenv_lmod_version()

   ------------------------------------------------------------------------
   --  The StandardPackage is where Lmod registers hooks.  Sites may
   --  override the hook functions in SitePackage.
   ------------------------------------------------------------------------
   require("StandardPackage")

   ------------------------------------------------------------------------
   -- Load a SitePackage Module.
   ------------------------------------------------------------------------

   local lmodPath = getenv("LMOD_PACKAGE_PATH") or ""
   for path in lmodPath:split(":") do
      path = path .. "/"
      path = path:gsub("//+","/")
      package.path  = path .. "?.lua;"      ..
                      path .. "?/init.lua;" ..
                      package.path

      package.cpath = path .. "../lib/?.so;"..
                      package.cpath
   end

   require("SitePackage")

   local cmdLineUsage = "Usage: module [options] sub-command [args ...]"
   Options:singleton(cmdLineUsage)
   local userCmd = masterTbl.pargs[1]
   table.remove(masterTbl.pargs,1)

   if (masterTbl.debug > 0 or masterTbl.dbglvl) then
      local configuration = require("Configuration"):singleton()
      io.stderr:write(configuration:report())
      local dbgLevel = max(masterTbl.debug, masterTbl.dbglvl or 1)
      dbg:activateDebug(dbgLevel)
   end

   if (dbg.active()) then
      dbg.start{"lmod(", concatTbl(arg," "),")"}
      dbg.print{"Date: ",os.date(),"\n"}
      dbg.print{"Hostname: ",posix.uname("%n"),"\n"}
      dbg.print{"System: ",posix.uname("%s")," ",posix.uname("%r"),"\n"}
      dbg.print{"Version: ",posix.uname("%v"),"\n"}
      dbg.print{"Lmod Version: ",Version.name(),"\n"}
      dbg.print{"package.path: ",package.path,"\n"}
      dbg.print{"lmodPath: ", lmodPath,"\n"}
   end
   -- dumpversion and quit if requested.

   if (masterTbl.dumpversion) then
      io.stderr:write(Version.tag(),"\n")
      os.exit(0)
   end

   -- gitversion and quit if requested.
   if (masterTbl.gitversion) then
      local gitV = Version.git()
      if (gitV == "") then
         gitV = Version.tag()
      else
         gitV = gitV:match('%((.*)%)')
      end
      io.stderr:write(gitV,"\n")
      os.exit(0)
   end

   -- print version and quit if requested.
   if (masterTbl.version) then
      io.stderr:write(version())
      os.exit(0)
   end

   -- print Configuration and quit.
   if (masterTbl.config) then
      local configuration = require("Configuration"):singleton()
      local a = {}
      a[1] = version()
      a[2] = configuration:report()
      pcall(pager,io.stderr,concatTbl(a,""))
      os.exit(0)
   end

   -- dump Configuration in json and quit.
   if (masterTbl.configjson) then
      local configuration = require("Configuration"):singleton()
      local a = {}
      a[#a+1] = configuration:report_json()
      a[#a+1] = ""
      io.stderr:write(concatTbl(a,"\n"))
      os.exit(0)
   end

   ------------------------------------------------------------
   -- Search for command, quit if command is unknown.
   local cmdT = false
   if (userCmd) then
      for _, v in ipairs(lmodCmdA) do
         if (userCmd:find(v[1])) then
            cmdT = v[2]
            break
         end
      end
   end

   hook.apply("startup", userCmd)

   local checkMPATH = (cmdT) and cmdT.checkMPATH or false
   dbg.print{"Calling Master:singleton(checkMPATH) w checkMPATH: ",checkMPATH,"\n"}
   master = Master:singleton(checkMPATH)

   -- Build Shell object from shellNm
   Shell = BaseShell:build(shellNm)
   dbg.print{"shellNm: ",shellNm,", Shell:name(): ",Shell:name(),"\n"}

   if (masterTbl.checkSyntax) then
      Shell:setActive(false)
   end

   -- Output local vars
   --Shell:expand(varTbl)

   -- if Help was requested then quit.
   if (masterTbl.cmdHelp) then
      Help()
      os.exit(0)
   end

   if (masterTbl.reportMT) then
      local mt = FrameStk:singleton():mt()
      io.stderr:write(mt:serializeTbl("pretty"),"\n")
      os.exit(0)
   end

   if (not cmdT) then
      io.stderr:write(version())
      io.stderr:write(Usage(),"\n")
      LmodErrorExit()
   else
      local cmd  = cmdT.cmd
      dbg.print{"cmd name: ", cmdT.name,"\n"}
      cmd(unpack(masterTbl.pargs))
   end

   ------------------------------------------------------------
   -- After running command reset frameStk and mt as the
   -- frameStk can be cleared during commands.  Also
   -- the module table (mt) is also on the frame stack
   -- and must be re-initialized!
   local frameStk = FrameStk:singleton()
   local mt       = frameStk:mt()

   -- Report any admin messages associated with loads
   -- Note that is safe to run every time.
   mcp:reportAdminMsgs()


   -- Report any changes (worth reporting from original MT)
   if (not quiet()) then
      mt:reportChanges()
   end

   local varT     = frameStk:varT()
   local n        = mt:name()
   varT[n]        = Var:new(n)
   varT[n]:set(mt:serializeTbl())

   ExitHookA.apply()
   dbg.fini("lmod")

   -- Output all newly created path and variables.
   Shell:expand(varT)

   if (Shell:real_shell())then
      Exec:exec():expand()
   end

   local t2 = epoch()
   timer:deltaT("main", t2 - t1)
   if (masterTbl.reportTimer) then
      io.stderr:write(timer:report(),"\n")
   end

   if (getWarningFlag() and not quiet() ) then
      LmodErrorExit()
   end
end

main()

