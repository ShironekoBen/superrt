set_global_assignment -entity "MainPLL" -library "lib_MainPLL" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "MainPLL" -library "lib_MainPLL" -name IP_TOOL_VERSION "18.1"
set_global_assignment -entity "MainPLL" -library "lib_MainPLL" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_MainPLL" -name SPD_FILE [file join $::quartus(sip_path) "MainPLL.spd"]

set_global_assignment -library "lib_MainPLL" -name MISC_FILE [file join $::quartus(sip_path) "MainPLL_sim/MainPLL.vo"]
