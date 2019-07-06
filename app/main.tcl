if {![info exists ::env(HOME)]} {
	set ::env(HOME) $::env(USERPROFILE)
}
set __VERSION__ 1.0.17.1
set __SRCDIR__ [file dirname [info script]]
if {![info exists __WRAPPED__]} {set __WRAPPED__ [file exists [info nameofexecutable]/app/main.tcl]}
set __WLIBDIR__ [info nameofexecutable]
set ::args $argv
if {${__WRAPPED__}} {
	set __EXEDIR__ [file dirname [info nameofexecutable]]
} else {
	set __EXEDIR__ ${__SRCDIR__}
}
if {$tcl_platform(platform) eq "windows"} {
	set __EXEEXT__ ".exe"
} else {
	set __EXEEXT__ ""
}

puts stderr "Pre-initialization sequence..."
package require Tk
package require Iwidgets
ttk::setTheme Arc
package require msgcat
package require tablelist
namespace import msgcat::*
if [catch {package require argparse}] {
	source ${__SRCDIR__}/argparse.tcl
}
source ${__SRCDIR__}/misc3rdparty.tcl
package require tepam

puts "LiteNote GUI (litenote-tk) ${__VERSION__} (C) 2019 Ronsor Labs, et al."
puts "                           ${__VERSION__} [mc "Copyright 2019 Ronsor Labs and others."]"
puts stderr "Loaded third-party libraries from [info library]"

source ${__SRCDIR__}/liblitecore.tcl
source ${__SRCDIR__}/icons.tcl

puts stderr "Loaded first-party libraries from ${__SRCDIR__}"

set params [dict merge [list \
	with-litenote-core [file join ${__EXEDIR__} litenoted${__EXEEXT__}] \
	core-args "" \
	core-url "http://127.0.0.1:9442/" \
	core-username null \
	core-password null \
	data-dir [file join $::env(HOME) .litenote-tk] \
	] [argparse -inline -long -equalarg [list \
	{-h|help} \
	{-with-litenote-core=} \
	{-core-args} \
]]]

if {[dict exists $params help]} {
	puts {
Usage: litenote-tk ?-h|--help? ?--with-litenote-core=/path/to/litenoted? ?--core-url=http://127.0.0.1:9442? ?--core-username=...? ?--core-password=...? ?--core-args=...?
                   ?--data-dir=$HOME/.litenote-tk?
}
	exit 1
}

catch {file mkdir [dict get $params data-dir]}

proc bgerror {message} {
	puts stderr "An internal error occurred (class: non-fatal): $message"
}


CoreRPC::init [dict get $params core-url] [dict get $params core-username] [dict get $params core-password] [dict get $params data-dir]

if {[dict get $params with-litenote-core] ne "no" && [catch {CoreRPC::getblockchaininfo}]} {
	set corePath [dict get $params with-litenote-core]
	set coreCmd [list ${corePath} \
		"--rpcpassword=[dict get $params core-password]" \
		"--rpcuser=[dict get $params core-username]" \
		{*}[dict get $params core-args]]
	puts stderr "with-litenote-core: invoke: $coreCmd"
	if {$tcl_platform(platform) eq "windows"} {
		set coreHndl [open "|cmd /c start /min [join $coreCmd " "]" w]
	} else {
		exec {*}$coreCmd &
	}
	after 1000
	while {[catch CoreRPC::getblockchaininfo]} {
		puts stderr "Waiting..."
		after 600
	}
}

wm title . [mc "LiteNote Client"]
wm geometry . 800x480

# MISC

# there's nothing here

# END MISC

# GENERAL ACTIONS

proc validateAddress v {
	if {![string is alnum $v]} {return 0}
	if {[string length $v] != 34 && [string length $v] != 33} {return 0}
	return 1
}

proc doSendMessage {{to ""} {subject ""} {body ""}} {
	set instance .doSendMessage[clock seconds][clock clicks]
	set ::to$instance $to
	set ::body$instance $body
	set ::subject$instance $subject
	toplevel $instance
	wm title $instance [mc "Compose Note"]
	wm geometry $instance 700x400
	ttk::frame $instance.f
	ttk::frame $instance.f.hdr
	ttk::label $instance.f.hdr.lblTo -text [mc "To"]
	ttk::entry $instance.f.hdr.to -textvariable to$instance -width 50
	ttk::label $instance.f.hdr.lblSubj -text [mc "Subject"]
	ttk::entry $instance.f.hdr.subj -textvariable subject$instance -width 50
	ttk::button $instance.f.hdr.send -text [mc "Send"] -command "set ::body$instance \[$instance.f.body get 1.0 end\]; destroy $instance; set ::send$instance 1"
	grid $instance.f.hdr.lblTo $instance.f.hdr.to
	grid $instance.f.hdr.lblSubj $instance.f.hdr.subj $instance.f.hdr.send
	pack $instance.f.hdr -fill x
	iwidgets::scrolledtext $instance.f.body
	$instance.f.body insert 1.0 [set ::body$instance]
	pack $instance.f.body -fill both -expand 1
	pack $instance.f -expand 1 -fill both
	tkwait window $instance
	if {[info exists ::send$instance]} {
		if {[catch {CoreRPC::sendmessage [set ::to$instance] [set ::subject$instance] [set ::body$instance]} errmsg]} {
			tk_messageBox -icon error -title "Error Sending Note" -message "$errmsg"
			doSendMessage [set ::to$instance] [set ::subject$instance] [set ::body$instance]
		}
	}
	catch {
		unset ::body$instance
		unset ::to$instance
		unset ::subject$instance
		unset ::send$instance
	}
}

proc doDisplayMessage msg {
	set to [dict get $msg to]
	set from [dict get $msg from]
	set body [dict get $msg body]
	set subject [dict get $msg subject]
	set instance .doDisplayMessage[clock seconds][clock clicks]
	set ::to$instance $to
	set ::from$instance $from
	set ::body$instance $body
	set ::subject$instance $subject
	toplevel $instance
	wm title $instance [mc "View Note: %s from %s" $subject $to]
	wm geometry $instance 700x400
	ttk::frame $instance.f
	ttk::frame $instance.f.hdr
	ttk::label $instance.f.hdr.lblTo -text [mc "To"]
	ttk::entry $instance.f.hdr.to -textvariable to$instance -width 50
	ttk::label $instance.f.hdr.lblFrom -text [mc "From"]
	ttk::entry $instance.f.hdr.from -textvariable from$instance -width 50
	ttk::label $instance.f.hdr.lblSubj -text [mc "Subject"]
	ttk::entry $instance.f.hdr.subj -textvariable subject$instance -width 50
	ttk::button $instance.f.hdr.send -text [mc "Reply"] -command [list doSendMessage $from "Re: $subject" "\n\nIn reply to:\n$body"]
	grid $instance.f.hdr.lblTo $instance.f.hdr.to
	grid $instance.f.hdr.lblFrom $instance.f.hdr.from
	grid $instance.f.hdr.lblSubj $instance.f.hdr.subj $instance.f.hdr.send
	pack $instance.f.hdr -fill x
	iwidgets::scrolledtext $instance.f.body
	$instance.f.body insert 1.0 [set ::body$instance]
	pack $instance.f.body -fill both -expand 1
	pack $instance.f -expand 1 -fill both
	tkwait window $instance
	catch {
		unset ::body$instance
		unset ::to$instance
		unset ::from$instsance
		unset ::subject$instance
	}
}

proc doSendCoins {} {
	set txAddr {}
	set txAmt 0.0
	set result [tepam::argument_dialogbox \
		-title [mc "New LiteNote Transaction"] \
		-entry [list -label [mc "To"] -variable txAddr] \
		-entry [list -label [mc "Amount"] -variable txAmt] \
	]
	if {$result eq "ok"} {
		puts stderr "Making transaction"
		if {[catch {CoreRPC::easysendtoaddress $txAddr $txAmt} errmsg]} {
			tk_messageBox -icon error -title [mc "Transaction Error"] -message $errmsg
		}
	} elseif {$result eq "cancel"} {
		return
	} else {
		tk_messageBox -icon error -title [mc "Error"] -message [mc "Something went very wrong!"]
	}
}

set ::isMining 0

proc doStartMining {} {
	set ::isMining 1
	statusBarUpdate
	internalStartMining
}

proc internalStartMining {} {
	if {!$::isMining} return
	CoreRPC::generate 1
	vwait CoreRPC::generateCallback
	puts stderr "Mined block: $CoreRPC::generateCallback"
	after 1 internalStartMining
}

# END GENERAL ACTIONS

# MENU

menu .mbar

menu .mbar.file -tearoff 0
.mbar add cascade -menu .mbar.file -label [mc File]
.mbar.file add command -label [mc "Transfer LiteNote Coins"] -command doSendCoins
.mbar.file add command -label [mc "Compose Note"] -command doSendMessage
.mbar.file add command -label Exit -command exit

menu .mbar.mining -tearoff 0
.mbar add cascade -menu .mbar.mining -label [mc Mining]
.mbar.mining add command -label [mc "Start Mining"] -command doStartMining
.mbar.mining add command -label [mc "Stop Mining"] -command {set ::isMining 0}

menu .mbar.help -tearoff 0
.mbar add cascade -menu .mbar.help -label [mc Help]
.mbar.help add command -label About -command {
	tk_messageBox -title [mc "About LiteNote Client"] -message [join [list \
		"LiteNote Client (C) 2017-2018 The RCoinX TkWallet Developers." \
		"LiteNote Client (C) 2017-2019 Ronsor Labs, et al." \
		[mc "Copyright 2019 Ronsor Labs and others."] \
		"" \
		[mc "Licensed under the MIT license."] \
		"https://litenote.ronsor.pw" \
	] "\n"] -icon info
}

# END MENU

# TOOLBAR

ttk::frame .toolbar
ttk::button .toolbar.compose -text [mc "Compose Note"] -command doSendMessage -image ::icons::email_go
ttk::button .toolbar.transfer -text [mc "Transfer LiteNote Coins"] -command doSendCoins -image ::icons::database_go
ttk::label .toolbar.lblinbox -text [mc "Inbox:"]
ttk::button .toolbar.newer -text [mc "Newer Notes"] -command {incr ::inbox_offset -100; if {$::inbox_offset < 0} {set ::inbox_offset 0}; myInboxUpdate}
ttk::button .toolbar.older -text [mc "Older Notes"] -command {if {[llength ${::.tabs.home.inbox}] == 250} {incr ::inbox_offset 100}; myInboxUpdate}

grid .toolbar.compose .toolbar.transfer .toolbar.lblinbox .toolbar.newer .toolbar.older

pack .toolbar -fill x

# END TOOLBAR

# NOTEBOOK

ttk::notebook .tabs

# HOME TAB

ttk::frame .tabs.home

ttk::labelframe .tabs.home.me -text [mc "My Account"]
ttk::label .tabs.home.me.lblAddress -text [mc "Primary Address:"] -font {{} 12 bold}
ttk::entry .tabs.home.me.address -width 40 -textvariable vPrimaryAddress
ttk::label .tabs.home.me.lblBalance -text [mc "Balance:"] -font {{} 12 bold}
ttk::label .tabs.home.me.balance -textvariable vBalance
ttk::label .tabs.home.me.lblBalanceAfter -text "XSN" -font {{} 12 bold}

grid x .tabs.home.me.lblAddress .tabs.home.me.address \
	.tabs.home.me.lblBalance .tabs.home.me.balance \
	.tabs.home.me.lblBalanceAfter x \
	 -padx 5 -pady 5

pack .tabs.home.me -fill x

proc myAccountUpdate {} {
	set winfo [CoreRPC::getwalletinfo]
	set addr [CoreRPC::getmainaddress]
	set ::vPrimaryAddress $addr
	set ::vBalance [expr {[dict get $winfo balance] + [dict get $winfo unconfirmed_balance]}]
	after 3000 myAccountUpdate
}

myAccountUpdate

ttk::frame .tabs.home.inbox

tablelist::tablelist .tabs.home.inbox.l \
	-columns [list 0 [mc "Date"] 0 [mc "Subject"] 35 [mc "From"] 35 [mc "To"] 0 [mc "ID"] 0 [mc "Unix Timestamp"]] \
	-listvariable ::.tabs.home.inbox \
	-xscrollcommand ".tabs.home.inbox.h set" -yscrollcommand ".tabs.home.inbox.v set"

bind .tabs.home.inbox.l <<TablelistSelect>> [list doInboxSelected %W]

ttk::scrollbar .tabs.home.inbox.v -orient vertical   -command {.tabs.home.inbox.l yview}
ttk::scrollbar .tabs.home.inbox.h -orient horizontal -command {.tabs.home.inbox.l xview}

pack .tabs.home.inbox.v -side right -fill y
pack .tabs.home.inbox.h -side bottom -fill x
pack .tabs.home.inbox.l -fill both -expand 1
pack .tabs.home.inbox -fill both -expand 1

proc doInboxSelected {w} {
	set sel [$w curselection]
	set row [lindex $sel 0]
	set id [$w getcells $row,4]
	doDisplayMessage [dict get ${::.tabs.home.inbox.raw} $id]
}

set ::inbox_offset 0

proc myInboxUpdate {} {
	set msgs [CoreRPC::listmessages $::inbox_offset 250]
	set ::.tabs.home.inbox {}
	foreach m $msgs {
		dict set ::.tabs.home.inbox.raw [dict get $m txid] $m
		lappend ::.tabs.home.inbox [list [clock format [dict get $m timestamp] -format "%b %d, %Y %r"] \
			[dict get $m subject] [dict get $m from] [dict get $m to] [dict get $m txid] [dict get $m timestamp]]
	}
	.tabs.home.inbox.l sortbycolumn 5 -decreasing
	after 10000 myInboxUpdate
}

myInboxUpdate

.tabs add .tabs.home -text [mc "Home"]

# END HOME TAB

# TRANSACTIONS TAB

ttk::frame .tabs.tx

.tabs add .tabs.tx -text [mc "Transactions"]

ttk::frame .tabs.tx.history

tablelist::tablelist .tabs.tx.history.l \
	-columns [list 0 [mc "Date"] 0 [mc "Type"] 0 [mc "Amount"] 35 [mc "From"] 35 [mc "To"] 0 [mc "ID"] 0 [mc "Unix Timestamp"]] \
	-listvariable ::.tabs.tx.history \
	-xscrollcommand ".tabs.tx.history.h set" -yscrollcommand ".tabs.tx.history.v set"

#bind .tabs.tx.history.l <<TablelistSelect>> [list doInboxSelected %W]

ttk::scrollbar .tabs.tx.history.v -orient vertical   -command {.tabs.tx.history.l yview}
ttk::scrollbar .tabs.tx.history.h -orient horizontal -command {.tabs.tx.history.l xview}

pack .tabs.tx.history.v -side right -fill y
pack .tabs.tx.history.h -side bottom -fill x
pack .tabs.tx.history.l -fill both -expand 1
pack .tabs.tx.history -fill both -expand 1

proc doTxHistoryUpdate {} {
	set ::oldtxlist {}
	set txlist [CoreRPC::listtransactions * 1000 0]
	if {$::oldtxlist ne $txlist} {
		set ::.tabs.tx.history {}
		foreach tx $txlist {
			lappend ::.tabs.tx.history \
				[list [clock format [dict getnull $tx time] -format "%b %d, %Y %r"] \
				[dict getnull $tx category] [dict getnull $tx amount] * [dict getnull $tx address] [dict getnull $tx txid] [dict getnull $tx time]]
		}
	}
	set ::oldtxlist $txlist
	.tabs.tx.history.l sortbycolumn 6 -decreasing
	after 3000 doTxHistoryUpdate
}

doTxHistoryUpdate

# END TRANSACTIONS TAB

# END NOTEBOOK

# STATUSBAR

proc statusBarUpdate {} {
	set bcInfo [CoreRPC::getblockchaininfo]
	set parts {}
	lappend parts [mc "Block Height: %d" [dict get $bcInfo headers]]
	lappend parts [mc "Mining Difficulty: %s" [dict get $bcInfo difficulty]]
	if {[dict get $bcInfo initialblockdownload]} {
		lappend parts [mc "Syncing with LiteNote network..."]
	}
	if {$::isMining} {
		lappend parts [mc "Mining blocks..."]
	}
	set ::statusBarText [join $parts " | "]
	after 3000 statusBarUpdate
}

statusBarUpdate

ttk::label .statusbar -textvariable statusBarText

# END STATUSBAR

# CONFIGURE WIDGETS

. configure -menu .mbar

pack .tabs -fill both -expand 1
pack .statusbar -fill x

# END CONFIGURE

puts stderr "Ready"

