# cbFTPtcl.tcl --
#
#	cbFTPtcl client implementation for Tcl.
#
# Copyright (c) 2019-2020 by MalaGaM <MalaGaM.ARTiSPRETiS>.
# This code SCENE may be distributed under the same terms as Tcl.

package require Tcl 8.6
package require base64 2.4.2
package require tls 1.7.16
package require udp 1.0.11
package require http 2.9.0
package require json 1.3.4
package require json::write 1.0.3



namespace eval ::cbFTPtcl {
    # counter used to differentiate connections
    variable config
    variable irctclfile [info script]
    array set config {
        debug			0
        logger			0
        PKGVersion		0.1
        PKGAuthor		"MalaGaM <MalaGaM.ARTiSPRETiS@GMail.Com>"
        PKGDescription	"cbFTP Client for TCL"
        WebSite			"https://cbftp.eu/"
        ScreenName		"cbFTP-TCL"
        ScreenPID		""
        ExecPath		"~/Softwares/cbftp/bin/cbftp"
        ExecVersion		""
        DataPath		"~/.cbFTPtcl/data"
    }
}

# ::cbFTPtcl::config --
# Set global configuration options.
# Arguments:
# key	name of the configuration option to change.
# value	value of the configuration option.

proc ::cbFTPtcl::config { args } {
    variable config
    if { [llength $args] == 0 } {
        return [array get config]
    } elseif { [llength $args] == 1 } {
        set key [lindex $args 0]
        return $config($key)
    } elseif { [llength $args] > 2 } {
        error "wrong # args: should be \"config key ?val?\""
    }
    # llength $args == 2
    set key [lindex $args 0]
    set value [lindex $args 1]
    foreach ns [namespace children] {
        if { [info exists config($key)] && [info exists ${ns}::config($key)] \
                    && [set ${ns}::config($key)] == $config($key)} {
            ${ns}::config $key $value
        }
    }
    set config($key) $value
}

proc ::cbFTPtcl::connect { {API ""} {OPT1 ""} {VAL1 ""} {OPT2 ""} {VAL2 ""}  {OPT3 ""} {VAL3 ""} } {
    variable config
    if {[llength $API] ==7} { foreach {API OPT1 VAL1 OPT2 VAL2 OPT3 VAL3} $API {} }
    set args [concat $OPT1 $VAL1 $OPT2 $VAL2 $OPT3 $VAL3]
    append err(usage)	"[lindex [info level 0] 0] ";
    append err(usage)	"<UDP|JSon> ";
    append err(usage)	"-host 127.0.0.1 ";
    append err(usage)	"-password MyPassWord ";
    append err(usage)	"-port 55477";
    
    set err(wrongNumArgs)	"wrong # args: should be \"$err(usage)\"";
    set err(valueMissing)	"value for \"%s\" missing: should be \"$err(usage)\""
    set err(unknownOpt)	"unknown option \"%s\": should be \"$err(usage)\"";
    
    set API	[string tolowe [lindex $API 0]]
    if { $API != "udp" && $API != "json"} { return -code error $err(wrongNumArgs); }
    
    # process arguments
    set len [llength $args]
    if {$len != 6} { return -code error $err(wrongNumArgs) }
    
    # Initialize parameters
    array set opts {-host {} -password {} -port {}}
    
    # process parameters
    for {set i 0} {$i < $len} {incr i} {
        set flag [lindex $args $i]
        incr i
        switch -glob -- $flag {
            "-host"	{
                set RE {^([1-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]).([1-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]).([1-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]).([1-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])|127.0.0.1}
                if {$i >= $len || ![regexp -all $RE [lindex $args $i] host]} {
                    return -code error [format $err(valueMissing) $flag]
                }
                set opts($flag) $host
            }
            "-password"	{
                if {$i >= $len} {
                    return -code error [format $err(valueMissing) $flag]
                }
                set opts($flag) [lindex $args $i]
            }
            "-port"	{
                set RE {^()([1-9]|[1-5]?[0-9]{2,4}|6[1-4][0-9]{3}|65[1-4][0-9]{2}|655[1-2][0-9]|6553[1-5])$}
                if {$i >= $len || ![regexp -all $RE [lindex $args $i] port]} {
                    return -code error [format $err(valueMissing) $flag]
                }
                lappend opts($flag) $port
            }
            default {
                return -code error [format $err(unknownOpt) [lindex $args $i]]
            }
        }
    }
    
    # Validate the parameters
    if {![llength $opts(-host)]} { return -code error [format $err(valueMissing) "-host"] }
    if {![llength $opts(-password)]} { return -code error [format $err(valueMissing) "-password"] }
    if {![llength $opts(-port)]} { return -code error [format $err(valueMissing) "-port"] }
    
    set config($API,hostname)	$opts(-host)
    set config($API,port)		$opts(-port)
    set config($API,password)	$opts(-password)
    
    return [::cbFTPtcl::config]
}

# ::cbFTPtcl::reload --
#
# Reload this file, and merge the current connections into
# the new one.

proc ::cbFTPtcl::reload { } {
    namespace eval :: { source [set ::cbFTPtcl::cbFTPtcltclfile] }
    foreach ns [namespace children] {
        foreach var {site logger host port} {
            set $var [set ${ns}::$var]
        }
        array set config [array get ${ns}::config]
        # make sure our new connection uses the same namespace
        ::cbFTPtcl::connection
        foreach var {site logger host port} {
            set ${ns}::$var [set $var]
        }
        array set ${ns}::config [array get config]
    }
}
proc ::cbFTPtcl::CORE:Install { } {
    variable config
    set INSTALLPATH		"[file normalize "~"]/Softwares/cbFTPtcl";
    if { ![file exist $INSTALLPATH] }  {
        file mkdir $INSTALLPATH
    } {
        file delete -force $INSTALLPATH
        file mkdir $INSTALLPATH
    }
    array set R [::cbFTPtcl::Check:VersionOnline];
    set f [open /tmp/${R(FileName)} wb]
    ::http::register https 443 [list ::tls::socket];
    set tok [http::geturl  "${config(WebSite)}/${R(FileName)}" -channel $f -binary 1]
    close $f
    ::http::unregister https
    if {[http::status $tok] eq "ok" && [http::ncode $tok] == 200} {
        putlog "Downloaded successfully :/tmp/${R(FileName)}"
    }
    http::cleanup $tok
    
    exec -- tar -C "$INSTALLPATH" -xf "/tmp/${R(FileName)}" --strip 1
    set CURPATH [pwd]
    cd $INSTALLPATH
    exec -- make
    cd $CURPATH
    
    file delete -force "/tmp/${R(FileName)}"
    return "cbFTPtcl ${R(Version} installed. Please reload package cbFTPtcl."
    
}


proc ::cbFTPtcl::Check { } {
    ::cbFTPtcl::Check:Exec
    ::cbFTPtcl::Check:Config
}
proc ::cbFTPtcl::Check:Exec { } {
    variable config
    set cbEXEC	 [file normalize $config(ExecPath)];
    if { ![file exists $cbEXEC] || ![file isfile $cbEXEC] || ![file executable $cbEXEC] } {
        return -code error "Problem with executable file '$cbEXEC'. Resolve with : ::cbFTPtcl::CORE:Install"
    }
    return $cbEXEC
}


proc ::cbFTPtcl::Check:Config { } {
    variable config
    set FILENAME	[file normalize $config(DataPath)]
    if { ![file exists $FILENAME] } {		return "$FILENAME not exists"		}
    if { ![file isfile $FILENAME] } {		return "$FILENAME not file"			}
    if { ![file readable $FILENAME] } {		return "$FILENAME not readable"		}
    if { ![file writable $FILENAME] } {		return "$FILENAME not writable "	}
    set fp [open $FILENAME r]
    set file_data [read $fp]
    close $fp
    incr i
    
    if { [regexp -all -line {RemoteCommandHandler.enabled=(.*)} $file_data Match Value] && [incr i] } {
        if { $Value == "false" } {
            return -code error "cbFTPtcl RemoteCommandHandler.enabled doit être sur 'true' dans $FILENAME"
        }
    }
    
    if { [regexp -all -line {HTTPServer.enabled=(.*)} $file_data Match Value] && [incr i] } {
        if { $Value == "false" } {
            return -code error "cbFTPtcl HTTPServer.enabled doit être sur 'true' dans $FILENAME"
        }
    }
    
    if { [regexp -all -line {RemoteCommandHandler.port=(\d+)} $file_data Match Value] && [incr i] } {
        set config(udp,port)		$Value
    }
    
    if { [regexp -all -line {RemoteCommandHandler.passwordb64=(.*)} $file_data Match Value] && [incr i] } {
        set config(udp,password)  [::base64::decode $Value]
        set config(json,password)  [::base64::decode $Value]
    }
    
    if { [regexp -all -line {HTTPServer.port=(\d+)} $file_data Match Value] && [incr i] } {
        set config(json,port)		$Value
    }
    return 1
}

# ::cbFTPtcl::init --
#
# Create an cbFTPtcl connection namespace and associated commands.


proc ::cbFTPtcl::Check:VersionOnline { } {
    variable config
    ::http::register https 443 [list ::tls::socket];
    set t		[http::geturl "${config(WebSite)}/index.html" -timeout 300]
    set data	[http::data $t]
    set httpCode	[http::ncode $t]
    ::http::cleanup $t
    ::http::unregister https
    set Changes ""
    set RE		{(.*)}
    regexp {(?i)<pre>([^<]+)} $data -> Changes
    set RE		{=(cbftp-(.*)\.tar.gz)>}
    if { [regexp -all -line $RE $data -> FileName Version] } {
        return [list FileName $FileName Number $Version Changes $Changes]
    } else {
        return -1
    }
    
}

proc ::cbFTPtcl::Check:GetVersion { } {
    variable config
    set FILENAME [file normalize $config(ExecPath)];
    if { ![file exists $FILENAME] || ![file readable $FILENAME] } { return -1 }
    set LVersion	[lindex [split [exec sh -c "strings $FILENAME | grep 'redist:'"] ":"] 1]
    return $LVersion
    
}
proc ::cbFTPtcl::Check:Version { } {
    variable config
    array set RVersion [::cbFTPtcl::Check:VersionOnline];
    set LVersion [::cbFTPtcl::Check:GetVersion]
    return "Local Version: $LVersion | Remote Version: ${RVersion(Number)} -> ${config(WebSite)}/${RVersion(FileName)}\n${RVersion(Changes)}"
}
proc ::cbFTPtcl::Screen:List { } {
    set filename /tmp/cbFTPtcl-screen-[pid].cfg
    catch {	exec screen -ls > $filename } {}
    set output [split [exec cat $filename] "\n"]
    catch { exec rm -f $filename}
    return $output
}
proc ::cbFTPtcl::Screen:Start { } {
    variable config
    set ScreenList [::cbFTPtcl::Screen:List]
    putlog "screen -d -m -S $config(ScreenName) [::cbFTPtcl::Check:Exec]"
    if {[lsearch -regex $ScreenList ".*$config(ScreenName).*"] < 0} {
        if {[catch {exec -- screen -d -m -S $config(ScreenName) [::cbFTPtcl::Check:Exec]} result]} {
            # non-zero exit status, get it:
            set status [lindex $::errorCode 2]
        } else {
            set ScreenList [::cbFTPtcl::Screen:List]
            set status 1
        }
    } else {
        # Already running
        return -1
    }
    if {[::cbFTPtcl::Screen:State] == 0 } { return -code error "::cbFTPtcl::Screen:Start (status: $status). Can't not run 'screen -d -m -S $config(ScreenName) [::cbFTPtcl::Check:Exec]'" }
    # Get and Set ScreenPID
    ::cbFTPtcl::Screen:GetPID
    
    return $status
}
proc ::cbFTPtcl::Screen:Stop { } {
    set cmdline "kill [::cbFTPtcl::Screen:GetPID]"
    if { [catch { exec /bin/sh -c $cmdline } msg]} {
        return -0
    } else {
        return 1
    }
}

proc ::cbFTPtcl::Screen:GetPID { } {
    variable config
    set ScreenList [::cbFTPtcl::Screen:List]
    set RE	"(\\d+)\\.($config(ScreenName))"
    if { [regexp $RE $ScreenList -> config(ScreenPID)] } {
        return $config(ScreenPID)
    } else {
        return NULL
    }
    
}
proc ::cbFTPtcl::Screen:State { } {
    variable config
    set ScreenList [::cbFTPtcl::Screen:List]
    if {[lsearch -regex $ScreenList ".*$config(ScreenName).*"] < 0} {
        return 0
    } else {
        return 1
    }
}
proc ::cbFTPtcl::init { {s ""} } {
    variable config
    variable site
    set ::site $s
    set status 1
    # Version
    set config(ExecVersion) [::cbFTPtcl::Check:GetVersion]
    # If state screen is NULL, start the screen
    if { ![::cbFTPtcl::Screen:State] } { ::cbFTPtcl::Screen:Start }
    
    array set config [array get ::cbFTPtcl::config]
    if { $config(logger) || $config(debug)} {
        package require logger
        variable logger
        set logger [logger::init [namespace tail [namespace current]]]
        if { !$config(debug) } { ${logger}::disable debug }
    }
    #namespace export Send:JSon
    ::cbFTPtcl::Check
    return $status
    
}
#########################################################
# Implemented user-side commands, meaning that these commands
# cause the calling user to perform the given action.
#########################################################


# config --
#
# Set or return per-connection configuration options.
#
# Arguments:
#
# key	name of the configuration option to change.
#
# value	value (optional) of the configuration option.

proc ::cbFTPtcl::config { args } {
    variable config
    variable logger
    
    if { [llength $args] == 0 } {
        return [array get config]
    } elseif { [llength $args] == 1 } {
        set key [lindex $args 0]
        return $config($key)
    } elseif { [llength $args] > 2 } {
        error "wrong # args: should be \"config key ?val?\""
    }
    # llength $args == 2
    set key [lindex $args 0]
    set value [lindex $args 1]
    if { $key == "debug" } {
        if {$value} {
            if { !$config(logger) } { config logger 1 }
            ${logger}::enable debug
        } elseif { [info exists logger] } {
            ${logger}::disable debug
        }
    }
    if { $key == "logger" } {
        if { $value && !$config(logger)} {
            package require logger
            set logger [logger::init [namespace tail [namespace current]]]
        } elseif { [info exists logger] } {
            ${logger}::delete
            unset logger
        }
    }
    set config($key) $value
}


proc ::cbFTPtcl::Send:UDP { CMD {ARGV1 ""} {ARGV2 ""} {ARGV3 ""} {ARGV4 ""} {ARGV5 ""} {ARGV6 ""} {ARGV7 ""} {ARGV8 ""} {ARGV9 ""} } {
    variable config
    if { ![info exists config(udp,hostname)] || ![info exists config(udp,port)] || ![info exists config(udp,password)] } {
        set err(usage)	"UDP ";
        append err(usage)	"-host 127.0.0.1 ";
        append err(usage)	"-password MyPassWord ";
        append err(usage)	"-port 55477";
        
        set ERR	"[lindex [info level 0] 0] Require information provide by\n"
        append ERR	"::cbFTPtcl::connect $err(usage)"
        
        return -code error $ERR
    }
    set s [udp_open];
    fconfigure $s -remote [list $config(udp,hostname) $config(udp,port)];
    puts $s "$config(udp,password) $CMD [string trim [list $ARGV1 $ARGV2 $ARGV3 $ARGV4 $ARGV5 $ARGV6 $ARGV7 $ARGV8 $ARGV9] " {}"]";
    close $s
}

proc ::cbFTPtcl::call:UDP { {CMD ""} {ARGV1 ""} {ARGV2 ""} {ARGV3 ""} {ARGV4 ""} {ARGV5 ""} {ARGV6 ""} {ARGV7 ""} {ARGV8 ""} } {
    variable config
    if { $CMD == "" } {
        return -code error "call:UDP <CMD> \[ARG\] \n CMD: <download|upload|fxp|race|distribute|prepare|raw|rawwithpath|idle|abort|delete|abortdeleteincomplete|reset|hardreset> \[ARG\]"
    }
    switch -nocase $CMD {
        download	{
            # Rename VARS
            set srcsite	$ARGV1
            set srcpath	$ARGV2
            set srcfile	$ARGV3
            
            if { ($srcpath == "") || $ARGV4 != "" } {
                set ERR	"call:UDP $CMD <srcsite> <srcpath> \[srcfile\]\n"
                append ERR	"This command will result in cbFTPtcl starting a transfer job for downloading\n"
                append ERR	"the specified item to your default download directory. The srcfile field is\n"
                append ERR	"optional, if omitted cbFTPtcl will use the base name of the srcpath as file name\n"
                append ERR	"The srcpath field can also be a section name, in which case srcfile must also\n"
                append ERR	"be specified"
                return -code error $ERR
            }
            Send:UDP $CMD $srcsite $srcpath $srcfile
        }
        upload	{
            # Rename VARS
            set srcpath	$ARGV1
            set dstsite	$ARGV2
            set dstpath	$ARGV3
            set srcfile	$ARGV4
            
            if { ($dstpath == "") || $ARGV5 != "" } {
                set ERR	"call:UDP $CMD <srcpath> <dstsite> <dstpath> \[srcfile\]\n"
                
                append ERR	"This command will result in cbFTPtcl starting a transfer job for uploading\n"
                append ERR	"the specified item to the specified site and path. The srcfile field is\n"
                append ERR	"optional, if omitted cbFTPtcl will use the base name of the srcpath as file name.\n"
                append ERR	"The dstpath field can also be a section name."
                return -code error $ERR
            }
            Send:UDP $CMD $srcpath $srcfile $dstsite $dstpath
            #upload <srcpath> [srcfile] <dstsite> <dstpath>
            
            
        }
        fxp	{
            return -code error "call:UDP $CMD <srcsite> <srcpath> <srcfile> <dstsite> <dstpath> \[dstfile\]"
            return -code error "call:UDP $CMD <srcpath> <srcfile> <dstsite> <dstpath> \[dstfile\] \[srcsite\]"
        }
        race	{
            return -code error "call:UDP $CMD <section> <file> <sitelist>"
            return -code error "call:UDP $CMD <section> <file> \[srcsite,srcsite2,..\]"
        }
        distribute	{
            return -code error "call:UDP $CMD <section> <file> \[srcsite,srcsite2,..\]"
            return -code error "call:UDP $CMD <section> <file> \[srcsite,srcsite2,..\]"
        }
        prepare	{
            return -code error "call:UDP $CMD <section> <file> \[srcsite,srcsite2,..\]"
        }
        raw	{
            set llength [llength $ARGV];
            if { $llength == 1 } {
                return "ok 1"
            } elseif { $llength == 2 } {
                return "ok 1"
            } else {
                return -code error "call:UDP $CMD <command> \[srcsite,srcsite2,..\]"
            }
        }
        rawwithpath	{
            return -code error "call:UDP $CMD <sitelist> <path> <command>"
            return -code error "call:UDP $CMD <path> <command> \[srcsite,srcsite2,..\]"
        }
        idle	{
            return -code error "call:UDP $CMD <sitelist> \[time\]"
            return -code error "call:UDP $CMD \[time\] \[srcsite,srcsite2,..\]"
        }
        abort	{
            return -code error "call:UDP $CMD <job>"
        }
        delete	{
            return -code error "call:UDP $CMD  <job> \[srcsite,srcsite2,..\]"
        }
        abortdeleteincomplete	{
            return -code error "call:UDP $CMD <job>"
        }
        reset	{
            return -code error "call:UDP $CMD <job>"
        }
        hardreset	{
            return -code error "call:UDP $CMD <job>"
        }
        default		{
            return -code error "call:UDP <CMD> \[ARG\] \n CMD: <download|upload|fxp|race|distribute|prepare|raw|rawwithpath|idle|abort|delete|abortdeleteincomplete|reset|hardreset> \[ARG\]"
        }
    }
}

proc ::cbFTPtcl::Send:JSon { URI {METHOD "GET"} {BODY ""} {TIMEOUT "7001"} } {
    variable config
    if { ![info exists config(json,hostname)] || ![info exists config(json,port)] || ![info exists config(json,password)] } {
        set err(usage)	"JSon ";
        append err(usage)	"-host 127.0.0.1 ";
        append err(usage)	"-password MyPassWord ";
        append err(usage)	"-port 55477";
        
        set ERR	"[lindex [info level 0] 0] Require information provide by\n"
        append ERR	"::cbFTPtcl::connect $err(usage)"
        
        return -code error $ERR
    }
    if { $URI == "" } { return -code error "call:JSon <URI> \[METHOD:GET,POST\]" }
    set URL			"https://$config(json,hostname):$config(json,port)$URI"
    set HEADERS		[list Authorization "Basic [base64::encode :$config(json,password)]"]
    set OPTS		"method $METHOD auth \"basic {} $config(json,password)\" format json"
    #return "http::geturl	$URL -headers $HEADERS -timeout $TIMEOUT -query $BODY -method [string toupper $METHOD]"
    
    ::http::register https $config(json,port) [list ::tls::socket];
    set t		[http::geturl	$URL				\
            -headers	$HEADERS	\
            -timeout	$TIMEOUT	\
            -query		$BODY				\
            -method		[string toupper $METHOD]]
    
    # WebServices Data
    set WSDATA		[http::data  $t]
    set WSCODE	[http::ncode $t]
    set WSSTATUS	[::http::status  $t]
    ::http::cleanup $t
    ::http::unregister https
    #return "-> $WSDATA -> $WSCODE -> $WSSTATUS"
    if { $WSDATA != "" } { set WSDATA	[json::json2dict $WSDATA] }
    # Valeur default
    
    dict set RESSOURCE http code $WSCODE
    dict set RESSOURCE http status $WSSTATUS
    dict set RESSOURCE successes result NULL
    dict set RESSOURCE failures result NULL
    # Analyse
    if { $WSCODE == "200" && [dict exists $WSDATA failures] } {
        dict set RESSOURCE failures [dict get $WSDATA failures]
        
        if {[dict exists $WSDATA successes] && [dict get $WSDATA successes] != ""} {
            dict set RESSOURCE successes {*}[dict get $WSDATA successes]
        }
    } elseif { $WSCODE == "200" && [dict exists $WSDATA successes] } {
        dict set RESSOURCE successes result $WSDATA
    } elseif { $WSCODE != "200" && [dict exists $WSDATA failures] } {
        dict set RESSOURCE failures result [dict get $WSDATA error]
    } elseif { [dict exists $WSDATA error] } {
        dict set RESSOURCE failures result [dict get $WSDATA error]
    } elseif { $WSCODE == "200" } {
        dict set RESSOURCE successes result $WSDATA
    } elseif { $WSCODE != "200" } {
        if {$WSCODE == 409} {
            dict set RESSOURCE failures result "Conflict : Ressource déja existante (surement)"
        } elseif {$WSCODE == 201} {
            dict set RESSOURCE successes result "Created : 	Requête traitée avec succès et création d’un document."
        } elseif {$WSCODE == 204} {
            dict set RESSOURCE successes result "No Content : Requête traitée avec succès mais pas d’information à renvoyer."
        } elseif {$WSCODE == 405} {
            dict set RESSOURCE failures result "Method Not Allowed : Méthode de requête non autorisée."
        } elseif {$WSCODE == 401} {
            dict set RESSOURCE failures result "Unauthorized : Une authentification est nécessaire pour accéder à la ressource."
        } else {
            dict set RESSOURCE failures result "Inconue dans cbftptcl"
        }
    }
    return $RESSOURCE
}

proc ::cbFTPtcl::JSon:SiteMod { site arg } {
    if {$arg == "" } { return -code error "[lindex [info level 0] 0] <SiteName> -<ValueName> <ValueContent> \[-<ValueName2> <ValueContent2>, ..\]\n Exemple  [lindex [info level 0] 0] Mysite -user MyName -password MyPassword" }
    set JSON ""
    # Desactive le json multi line, tout arguement sur la meme ligne
    ::json::write indented 0
    ::json::write aligned 0
    set RE {-(addresses|affils|allow_download|allow_upload|base_path|broken_pasv|cepr|cpsv|disabled|except_source_sites|except_target_sites|force_binary_mode|leave_free_slot|list_command|max_idle_time|max_logins|max_sim_down|max_sim_down_complete|max_sim_down_pre|max_sim_down_transferjob|max_sim_up|password|pret|priority|proxy_name|proxy_type|skiplist|sscn|stay_logged_in|tls_mode|tls_transfer_policy|transfer_protocol|transfer_source_policy|transfer_target_policy|user|xdupe)\s+([^-]+)}
    set matchcount	[regexp -all -nocase -- $RE $arg]
    for {set x 0} {$x<$matchcount} {incr x} {
        if { [regexp -nocase -- $RE $arg Match ValueName ValueContent] && [regsub -all -nocase -- $Match $arg {} arg] } {
            set JName		[string tolower [string trim $ValueName]]
            set JValue		[string trim $ValueContent]
            set JValueCount	[llength $JValue]
            if { $JValue == "" } {		return -code error "Not value recieve for '$JName'" }
            if { $JValueCount != 1 } {	return -code error "Multi-Value not allow for '$JName' -> '$JValue'" }
            
            # Verification que les valeur sont propre pour le WS cbftp.
            # Rejet des valeurs incorrect et modification a la case
            
            ## addresses
            ## Plusieurs adresse peuvent etre fournis, seulement sous forme de "ip:port" -> "ip1:port1 ip2:port2 ip3port3 "
            if { $JName == "addresses" } {
                set addresses	" addresses \[::json::write array"
                # "addresses [::json::write array [::json::write string "ARGV2:ARGV3"] [::json::write string "ARGV2:ARGV3"]]"
                
                for {set a 0} {$a<$JValueCount} {incr a} {
                    set adressestmp [lindex $JValue $a]
                    # REGEXP IPorHOST:PORT validator
                    set adressesRE {^(([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9])\.)*([a-z0-9]|[a-z0-9][a-z0-9\-]*[a-z0-9]+\.[a-z0-9]+):([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$}
                    if { ![regexp -nocase -- $adressesRE $adressestmp] } {
                        set EXPLAIN		"Address: the hostname or IP address and port of your site. This field\n"
                        append EXPLAIN	"supports multiple values if a site has multiple entry addresses available,\n"
                        append EXPLAIN	"and they can be entered on the same line by separating them with spaces.\n"
                        append EXPLAIN	"TLS mode: Whether the site should be connected to securely with TLS. Note\n"
                        append EXPLAIN	"that not all FTP servers support this - it depends on the server whether it\n"
                        append EXPLAIN	"works or not."
                        set ERR			"with value '-addresses $adressestmp' is not <IP|HOSTNAME:PORT>"
                        return -code error "ERROR : $ERR\nEXPLAIN: $EXPLAIN"
                    }
                    set addresses [concat $addresses "\[::json::write string $adressestmp\]"]
                }
                set addresses [concat $addresses "\]"]
                set JSON [concat $JSON $addresses]
                continue
            }
            if { $JName == "allow_download" && [lsearch -nocase [list "YES" "NO" "MATCH_ONLY" "1" "0"] $JValue] == -1 } {
                set EXPLAIN		"allow_download: Authorize the download on the site."
                set ERR			"bad value. SYNTAXE '-$ValueName <YES|NO|MATCH_ONLY>'"
                return -code error "ERROR : $ERR\nEXPLAIN: $EXPLAIN"
            } elseif { $JName == "allow_download" && [lsearch -nocase [list "YES" "NO" "MATCH_ONLY" "1" "0"] $JValue] != -1 } {
                set JValue	[string map {"1" "yes" "0" "no"} [string tolower $JValue]]
                set JSON [concat $JSON "$JName \[::json::write string $JValue\]"]
                continue
                
            }
            if { $JName == "allow_upload" && [lsearch -nocase [list "YES" "NO" "1" "0"] $JValue] == -1 } {
                set EXPLAIN		"allow_download: Authorize the upload on the site."
                set ERR			"bad value. SYNTAXE '-$ValueName <YES|NO|1|0>'"
                return -code error "ERROR : $ERR\nEXPLAIN: $EXPLAIN"
            } else {
                set JValue	[string map {"1" "yes" "0" "no"} [string tolower $JValue]]
                
            }
            if { $JName == "list_command" && [lsearch -nocase [list "STAT_L" "LIST"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : STAT_L or LIST" } else { set JValue	[string toupper $JValue] }
            if { $JName == "priority" && [lsearch -nocase [list "VERY_LOW" "LOW" "NORMAL" "HIGH" "VERY_HIGH"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : VERY_LOW/LOW/NORMAL/HIGH/VERY_HIGH" } else { set JValue	[string toupper $JValue] }
            if { $JName == "proxy_type" && [lsearch -nocase [list "GLOBAL" "NONE" "USE"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : GLOBAL/NONE/USE" } else { set JValue	[string toupper $JValue] }
            if { $JName == "tls_mode" && [lsearch -nocase [list "NONE" "AUTH_TLS" "IMPLICIT"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : NONE/AUTH_TLS/IMPLICIT" } else { set JValue	[string toupper $JValue] }
            if { $JName == "tls_transfer_policy" && [lsearch -nocase [list "ALWAYS_OFF" "PREFER_OFF" "PREFER_ON"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : ALWAYS_OFF/PREFER_OFF/PREFER_ON" } else { set JValue	[string toupper $JValue] }
            if { $JName == "transfer_protocol" && [lsearch -nocase [list "IPV4_ONLY" "PREFER_IPV4" "PREFER_IPV6"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : IPV4_ONLY/PREFER_IPV4/PREFER_IPV6" } else { set JValue	[string toupper $JValue] }
            if { ($JName == "transfer_source_policy" || $JName == "transfer_target_policy") && [lsearch -nocase [list "ALLOW" "BLOCK"] $JValue] == -1 } { return -code error "$JValue is not allowed value for $JName , only : ALLOW/BLOCK" } else { set JValue	[string toupper $JValue] }
            if { [lsearch -nocase [list "broken_pasv" "cepr" "cpsv" "disabled" "force_binary_mode" "leave_free_slot" "pret" "sscn" "stay_logged_in" "xdupe"] $JName] != -1 && [lsearch -nocase [list "TRUE" "FALSE" "1" "0"] $JValue] == -1 } {
                return -code error "$JValue is not allowed value for $JName , only : TRUE or FALSE"
            } else {
                set JValue	[string map {"1" "true" "0" "false"} [string tolower $JValue]]
                # set JSON [concat $JSON "$JName $JValue"]
                set JSON [concat $JSON "$JName \[::json::write string $JValue\]"]
                continue
            }
        }
        set JSON [concat $JSON "$JName \[::json::write string $JValue\]"]
    }
    
    set JSON [concat "::json::write object"  $JSON]
    #return $JSON
    set RE {-(addresses|affils|allow_download|allow_upload|base_path|broken_pasv|cepr|cpsv|disabled|except_source_sites|except_target_sites|force_binary_mode|leave_free_slot|list_command|max_idle_time|max_logins|max_sim_down|max_sim_down_complete|max_sim_down_pre|max_sim_down_transferjob|max_sim_up|password|pret|priority|proxy_name|proxy_type|skiplist|sscn|stay_logged_in|tls_mode|tls_transfer_policy|transfer_protocol|transfer_source_policy|transfer_target_policy|user|xdupe)}
    set matchcount	[regexp -all -nocase -- $RE [string trim $arg]]
    for {set x 0} {$x<$matchcount} {incr x} {
        set arg	[string trim $arg]
        #return -code error "ERROR : inconnue\nEXPLAIN: $arg"
        if { [regexp -nocase -- $RE $arg Match ValueName] && [regsub -all -nocase -- $Match $arg {} arg] } {
            if { $ValueName == "addresses"} {
                set EXPLAIN		"Address: the hostname or IP address and port of your site. This field\n"
                append EXPLAIN	"supports multiple values if a site has multiple entry addresses available,\n"
                append EXPLAIN	"and they can be entered on the same line by separating them with spaces.\n"
                append EXPLAIN	"TLS mode: Whether the site should be connected to securely with TLS. Note\n"
                append EXPLAIN	"that not all FTP servers support this - it depends on the server whether it\n"
                append EXPLAIN	"works or not."
                set ERR			"SYNTAXE '-$ValueName <IP|HOSTNAME:PORT>'"
                
            }
            if { $ValueName == "affils"} {
                set EXPLAIN		"Affils: Which groups that pre on the site. Set this list properly to avoid\n"
                append EXPLAIN	"uploading into affil releases."
                set ERR			"SYNTAXE '-$ValueName <group>'"
                
            }
            if { $ValueName == "allow_download"} {
                set EXPLAIN		"allow_download: Authorize the download on the site."
                set ERR			"SYNTAXE '-$ValueName <YES|NO|MATCH_ONLY>'"
                
            }
            if { $ValueName == "allow_upload"} {
                set EXPLAIN		"allow_upload: Authorize the upload on the site."
                set ERR			"SYNTAXE '-$ValueName <YES|NO>'"
                
            }
            return -code error "ERROR : $ERR\nEXPLAIN: $EXPLAIN"
        }
    }
    if {$arg != ""} {
        return -code error "Nous avons pas su traité toute les commandes: $arg"
    }
    #return [eval $JSON]
    return [::cbFTPtcl::Send:JSon "/sites/$site" "PATCH" [eval $JSON]]
}
proc ::cbFTPtcl::call:JSon { {CMD ""} {ARGV1 ""} {ARGV2 ""} {ARGV3 ""} {ARGV4 ""} {ARGV5 ""} {ARGV6 ""} {ARGV7 ""} {ARGV8 ""} {ARGV9 ""} } {
    variable config
    
    if { ![info exists config(json,hostname)] || ![info exists config(json,port)] || ![info exists config(json,password)] } {
        set err(usage)		"JSon ";
        append err(usage)	"-host 127.0.0.1 ";
        append err(usage)	"-password MyPassWord ";
        append err(usage)	"-port 55477";
        
        set ERR	"[lindex [info level 0] 0] Require information provide by\n"
        append ERR	"::cbFTPtcl::connect $err(usage)"
        
        return -code error $ERR
    }
    # Desactive le json multi line, tout arguement sur la meme ligne
    ::json::write indented 0
    ::json::write aligned 0
    
    #if { $CMD == "" } { return -code error "call:JSon <CMD> \[ARG\] \n CMD: <SiteList> \[ARG\]" }
    switch -nocase $CMD {
        "siteinfo"	{
            if {$ARGV1 == "" } {  return -code error "[lindex [info level 0] 0] $CMD <SiteName>" }
            return [Send:JSon "/sites/$ARGV1"]
        }
        "sitedel"	{
            if {$ARGV1 == "" } {  return -code error "[lindex [info level 0] 0] $CMD <SiteName>" }
            return [Send:JSon "/sites/$ARGV1" "DELETE"]
        }
        "sitemod"	{
            return [::cbFTPtcl::JSon:SiteMod $ARGV1 [string trim "$ARGV2 $ARGV3 $ARGV4 $ARGV5 $ARGV6 $ARGV7 $ARGV8 $ARGV9"]]
        }
        "sitelist"	{ return [Send:JSon "/sites"] }
        "filelist"	{
            if {$ARGV1 == "" } {  return -code error "[lindex [info level 0] 0] $CMD <SiteName> \[SitePath\] \[SiteTimeOut\]" }
            if { $ARGV2 == ""} { set SitePath "/" } else { set SitePath $ARGV2 }
            if { $ARGV3 == ""} { set SiteTimeOut "10" } else { set SiteTimeOut $ARGV3 }
            return [Send:JSon "/filelist?site=${ARGV1}&path=${SitePath}&timeout=${SiteTimeOut}"]
            
        }
        "siteadd"	{
            if {$ARGV5 == "" } {  return -code error "[lindex [info level 0] 0] $CMD <SiteName> <USER> <PASSWORD> <HOST> <PORT>" }
            set BODY [::json::write object	\
                    name		[::json::write string $ARGV1]			\
                    password	[::json::write string "$ARGV3"]			\
                    user		[::json::write string "$ARGV2"]			\
                    addresses	[::json::write string "$ARGV4:$ARGV5"]]
            return [Send:JSon "/sites" "POST" $BODY]
        }
        "siteraw"	{
            # - Send a raw command
            # POST /raw
            
            # An example body when sending a raw command:
            
            # {
            # "command": "site deluser me",
            # "sites": [              // run on these sites
            # "SITE1"
            # ],
            # "site_with_sections": [ // run on sites with these sections defined
            # "SEC1"
            # ],
            # "sites_all": true,      // run on all sites
            # "path": "/some/path",   // the path to cwd to before running command
            # "path_section": "SEC1", // section to cwd to before running command
            # "timeout": 10,          // max wait before failing
            # "async": false          // if false, wait for command to finish before
            # // responding. If true, respond with a request
            # // id and let command run in the background
            # }
            
            # - Get raw command results for an async raw command with id 1
            # GET /raw/1
            if {$ARGV2 == "" } {  return -code error "[lindex [info level 0] 0] $CMD <SiteName> <cmd>" }
            set BODY [::json::write object	\
                    sites		[::json::write string $ARGV1]			\
                    command	[::json::write string [string trim "$ARGV2 $ARGV3 $ARGV4 $ARGV5"]]]
            return [Send:JSon "/raw" "POST" $BODY]
        }
        
        default		{ return -code error "[lindex [info level 0] 0] <CMD> \[ARG\] \n CMD: <sitelist|siteinfo|siteadd|sitemod|sitedel|siteraw|filelist|..> \[ARG\]" }
    }
}

proc ::cbFTPtcl::log {level text} {
    variable logger
    if { ![info exists logger] } return
    ${logger}::$level $text
}

proc ::cbFTPtcl::logname { } {
    variable logger
    if { ![info exists logger] } return
    return $logger
}

# destroy --
#
# destroys the current connection and its namespace

proc ::cbFTPtcl::destroy { } {
    variable logger
    variable site
    if { [info exists logger] } { ${logger}::delete }
    catch {close $site}
    namespace delete [namespace current]
}


proc ::cbFTPtcl::connected { } {
    variable site
    if { $site == "" } { return 0 }
    return 1
}

proc ::cbFTPtcl::site { s } {
    variable site
    set site $s
    return 1
}

proc ::cbFTPtcl::raw { Command } {
    variable config
    set s [udp_open];
    fconfigure $s -remote [list $cbFTPtcl(Hostname) $cbFTPtcl($Port)];
    puts $s "$cbFTPtcl($Password) $arg";
    close $s
}

proc ::cbFTPtcl::current { } {
    variable site
    return $site
}


# -------------------------------------------------------------------------
package provide cbFTPtcl $::cbFTPtcl::config(PKGVersion)
putlog "\[Loaded\] Package cbFTPtcl V$::cbFTPtcl::config(PKGVersion) - $::cbFTPtcl::config(PKGDescription) by $::cbFTPtcl::config(PKGAuthor)"
# -------------------------------------------------------------------------