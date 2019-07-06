package require Itcl
package require JSONRPC
package require rpcvar
package require mime
package require json
package require json::write
package require math::decimal
package require sqlite3

namespace eval CoreRPC {
	proc MSG_FLAG_ENCRYPTED {} {return 1}
	proc MSG_FLAG_UNSIGNED {} {return 2}
	proc MSG_FLAG_FROMSEGWIT {} {return 4}
	proc MSG_FLAG_DELETED {} {return 65536} ; # can't be specified in a message to be sent (not permitted!)
	proc init {url user pass datadir} {
		set ::CoreRPC::datadir $datadir
		puts stderr "Data dir: $datadir"
		sqlite3 ::CoreRPC::msgdb [file join $datadir msgcache.db] -create 1
		::CoreRPC::msgdb eval {
			PRAGMA application_id = 0x117E507E;
			PRAGMA user_version = 0x10171;
			CREATE TABLE IF NOT EXISTS messages(txid TEXT PRIMARY KEY, `from` TEXT, `to` TEXT, subject TEXT, body TEXT, timestamp INT, raw TEXT, flags INT);
			CREATE TABLE IF NOT EXISTS metatable(mkey TEXT PRIMARY KEY, valstr TEXT, valint INTEGER);
		} ;# Message database: magic: 0x117E507E (LITENOTE), version 1.0.17.1
		catch { ::CoreRPC::msgdb eval {
			INSERT INTO metatable VALUES('lasttx', '', 0);
		} }
		JSONRPC::configure -transport http -headers [list "Authorization" "Basic [binary encode base64 "$user:$pass"]"]
		foreach fn {
			getblockchaininfo
			getwalletinfo
			getrawchangeaddress
			getbalance
			estimatesmartfee
			listunspent
		} { JSONRPC::create $fn -proxy $url }
		JSONRPC::create getaddressesbylabel -proxy $url -params {label string}
		JSONRPC::create getnewaddress -proxy $url -params {label string type string}
		JSONRPC::create dumpprivkey -proxy $url -params {address string}
		JSONRPC::create sendtoaddress -proxy $url -params {address string amount string comment string comment_to string
									subtractfeefromamount boolean replaceable boolean}
		JSONRPC::create gettransaction -proxy $url -params {txid string}
		JSONRPC::create estimatesmartfee -proxy $url -params {conf_target int}
		JSONRPC::create generate -proxy $url -params {nblocks int} -command {set ::CoreRPC::generateCallback}
		JSONRPC::create createrawtransaction -proxy $url -params {p1 any p2 any}
		JSONRPC::create signrawtransactionwithkey -proxy $url -params {p1 string p2 any}
		JSONRPC::create signrawtransactionwithwallet -proxy $url -params {p1 string}
		JSONRPC::create sendrawtransaction -proxy $url -params {tx string}
		JSONRPC::create signmessagewithprivkey -proxy $url -params {privkey string message string}
		JSONRPC::create verifymessage -proxy $url -params {address string signature string message string}
		JSONRPC::create listtransactions -proxy $url -params {label string count int offset int}
		_messageindexingservice
	}
	proc easysendtoaddress {address amount {target 4}} {
		set fee 0.0001
		catch {
			set fee [dict get [estimatesmartfee $target] feerate]
		}
		sendtoaddress $address $amount "" "" 0 0
	}
	proc sendmessage {to subject body {encrypt 0} {from ""} {target 4}} {
		if {$to eq ""} {error "You need to enter a recipient address"}
		set fee 0.0001
		catch {
			set fee [dict get [estimatesmartfee $target] feerate]
		}
		if {$from eq ""} {set from [getmainaddress]}
		set privkey [dumpprivkey $from]
		set headerHex [binary encode hex "LNMSGV2"] ;# Message Packet header
		set unsignedmsg [json::write object \
			timestamp [clock seconds] \
			subject [json::write string $subject] \
			body [json::write string $body]]
		set signedmsg [json::write object \
			from [json::write string $from] \
			flags 0 \
			to [json::write string $to] \
			signature [json::write string [signmessagewithprivkey $privkey $unsignedmsg]] \
			payload [json::write string $unsignedmsg]]
		set payload $headerHex[binary encode hex $signedmsg] ;# Binary payload
		set utxo [listunspent]
		if {[llength $utxo] == 0} {
			error "Insufficient funds to send message"
		}
		set ok 0
		foreach itm $utxo {
			puts stderr "Debug: utxo amount: [dict get $itm amount]"
			if {[dict get $itm amount] > ($fee * 2) && ![info exists ::CoreRPC::used([dict get $itm txid])] && [dict get $itm safe]} {
				set utxo $itm
				set ok 1
				break
			}
		}
		if {!$ok} {
			error "Insufficient funds to send message"
		}
		set caddr [getrawchangeaddress]
		set retamt [math::decimal::tostr [math::decimal::- [math::decimal::fromstr [dict get $utxo amount]] [math::decimal::fromstr $fee]]]
		puts $itm
		set rawtx [createrawtransaction "\[{\"txid\":\"[dict get $utxo txid]\", \"vout\":[dict get $utxo vout]}\]" \
						"{\"data\":\"$payload\", \"$caddr\": \"$retamt\"}"]
		set signedtx [signrawtransactionwithwallet $rawtx]
		puts [sendrawtransaction [dict get $signedtx hex]] ;# wew that was a lot of work
		set ::CoreRPC::used([dict get $utxo txid]) 1
		after 1 ::CoreRPC::_messageindexingservice
	}
	proc parsehexmessage {msg} {
		set msg [string map {"OP_RETURN " ""} $msg]
		set msg [binary decode hex $msg]
		set txt [string range $msg 7 end]
		set ret ""
		switch -glob -- $msg {
			LNMSGV2* {
				set wrapper [json::json2dict $txt]
				if {![verifymessage [dict get $wrapper from] [dict get $wrapper signature] [dict get $wrapper payload]]} {
					error "Invalid message signature"
				}
				set ret [list from [dict get $wrapper from] to [dict get $wrapper to] wrapper $wrapper \
						flags [dict get $wrapper flags] {*}[json::json2dict [dict get $wrapper payload]]]
			}
			default {
				error "This is an invalid message"
			}
		}
		return $ret
	}

	proc getmainaddress {} {
		set addr "<error>"
		if {[catch {
			set addrlist [getaddressesbylabel "mainlegacy"]
			set addr [lindex $addrlist 0]
		}]} {
			set addr [getnewaddress "mainlegacy" "legacy"] ;# ...
		}
		return $addr
	}

	proc _messageindexingservice {} {
		after 1 ::CoreRPC::_messageindexingservice_loop
	}

	proc _messageindexingservice_loop {} {
		set lasttx "<error>"
		set txmagic 4c4e4d534756327 ;# "LNMSGV2" magic value marks beginning of message
		msgdb eval {SELECT valint FROM metatable WHERE mkey = 'lasttx'} values {
			set lasttx $values(valint)
		}
		if {$lasttx eq "<error>"} {error "Internal fault code 0x-1"}
		set totaltx [dict get [getwalletinfo] txcount]
		set amt [expr {$totaltx - $lasttx}]
		set newm [listtransactions "*" $amt 0]
		#puts stderr "msgindex: $amt (total $totaltx, last $lasttx) new transactions"
		foreach {tx} $newm {
			if {[catch {
			set txid [dict get $tx txid]
			set txfull [gettransaction $txid]
			set txhex [dict get $txfull hex]
			set idx [string first $txmagic $txhex]
			if {$idx == -1} continue
			set full [string range $txhex $idx end]
			if {[catch {set decoded [parsehexmessage $full]} errmsg]} {
				puts stderr "An invalid message was found on the blockchain ($txid):\n$errmsg"
				continue
			}
			# ---
			set pfrom [dict get $decoded from]
			set pto [dict get $decoded to]
			set pflags [dict get $decoded flags]
			set psubj [dict get $decoded subject]
			set pbody [dict get $decoded body]
			set pts [clock seconds]
			catch {set pts [dict get $decoded timestamp]}
			set praw " $decoded"
			msgdb eval {INSERT OR REPLACE INTO messages VALUES($txid, $pfrom, $pto, $psubj, $pbody, $pts, $praw, $pflags)}
			} errmsg]} {
				if {$errmsg ne ""} { puts stderr "An error occurred while indexing messages: $errmsg" }
			}
		}
		msgdb eval {INSERT OR REPLACE INTO metatable VALUES('lasttx', '', $totaltx)}
		after 1000 ::CoreRPC::_messageindexingservice_loop
	}

	proc listmessages {{offset 0} {limit 100}} {
		set ret {}
		msgdb eval {SELECT * FROM messages LIMIT $limit OFFSET $offset} values {
			catch {unset values(*)}
			lappend ret [array get values]
		}
		return $ret
	}
}

