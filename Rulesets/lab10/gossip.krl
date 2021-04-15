ruleset gossip {
	meta {
		name "Gossip"
		author "Nate Teahan"

		use module io.picolabs.subscription alias subscription

		shares getCurrentPeerState, getPeerViolationStates, getProcess, getSequenceNumber, getPicoID, getMissingMessages, getPeer, exceedingThreshold, getSchedule, tempLogs, peers, newMessage, newRumorMessage, newSeenMessage
	}

	global {
        getCurrentPeerState = function() {
			ent:peerState
		}

        getProcess = function() {
			ent:process.defaultsTo("on") == "on"
		}

        getSequenceNumber = function(id) {
			split = id.split(re#:#)
			split[split.length()-1].defaultsTo("0").as("Number")
		}

        getPicoID = function() {
			meta:picoId
		}

        getMissingMessages = function(peer) {
			eci = peer{"Tx"}
			peerState = ent:peerState{eci}.defaultsTo({})
			msgs = ent:messages.map(function(msgs, sensorID) {
				msgs.filter(function(msg, msgID) {
					getSequenceNumber(msgID) > peerState{sensorID}.defaultsTo(-1)
				})
			}).map(function(msgs, sensorID) {
				msgs.values()
			}).values().reduce(function(a, b) {
				a.defaultsTo([]).append(b)
			})

			msgs
		}

        getPeer = function() {
			peers = peers()

			// find all peers missing something
			missing = peers.map(function(peer) {
				peer.put("missing", getMissingMessages(peer).length())
			}).filter(function(peer) {
				peer{"missing"} > 0
			})

			// return a peer that is missing information, else a random peer
			peer = (missing.length() > 0 && random:integer(99) < 60)
				=> missing[random:integer(missing.length()-1)] // return a missing peer
				| peers[random:integer(peers.length()-1)] // return a random peer
			peer
		}

		exceedingThreshold = function() {
			ent:inTempViolation
		}

		getPeerViolationStates = function() {
			tempLogs().map(function(msgs, sensorID) {
				msgs.filter(function(msg, msgID) {
					msg{"type"} == "nodes_in_temp_violation" && msg{["payload", "add"]}
				}).values().reduce(function(sum, msg) {
					sum + msg{["payload", "add"]}
				}, 0)
			}).map(function(state) {
				state == 1
			})
		}

		peers = function() {
			subscription:established("Rx_role", "gossip_node")
		}

		tempLogs = function() {
			ent:messages
        }

		newMessage = function(peer) {
			type = random:integer(99)
			msg = (type < 80 && getMissingMessages(peer).length() > 0) => newRumorMessage(peer) | newSeenMessage()
			msg
		}

		newRumorMessage = function(peer) {
			missing = getMissingMessages(peer)

			// pick a message at random (there is at least one, see newMessage())
			msg = missing[random:integer(missing.length()-1)]
			msg
		}

		newSeenMessage = function() {
			// figure out the highest consecutive seq seen for each sensor
			seqs = tempLogs().map(function(msgs, sensorID) {
				msgs.keys().map(function(msgID) {
					getSequenceNumber(msgID)
				}).sort().reduce(function(a, b) {
					(a+1 == b) => b | a
				})
			})

			seqs
		}

        getSchedule = function() {
			schedule:list().filter(function(x) {
				x{"type"} == "repeat" && x{["event", "domain"]} == "gossip" && x{["event", "name"]} == "heartbeat"
			}).head(){"id"}
		}
	}

	rule init {
		select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid

		always {
			raise nuke event "gossip"
			raise gossip event "heartbeat"
		}
	}

	rule set_heartbeat_period {
		select when gossip set_heartbeat_period

		always {
			ent:period := event:attrs{"period"}.defaultsTo(ent:period)
		}
	}

	rule on_heartbeat {
		select when gossip heartbeat where getProcess()

		pre {
			peer = getPeer().klog("selected peer")
			msg = newMessage(peer).klog("sending message")
			type = (msg >< "messageID") => "rumor" | "seen"
		}

		if peer then
			event:send({
				"eci": peer{"Tx"},
				"domain": "gossip",
				"type": type,
				"attrs": {
					"peer": peer,
					"msg": msg
				}
			})
	}

	rule handle_rumor {
		select when gossip rumor where getProcess()

		pre {
			msgID = event:attrs{["msg", "messageID"]}
			sensorID = event:attrs{["msg", "sensorID"]}
			time = event:attrs{["msg", "timestamp"]}
			type = event:attrs{["msg", "type"]}
			payload = event:attrs{["msg", "payload"]}

			msg = {
				"messageID": msgID,
				"sensorID": sensorID,
				"timestamp": time,
				"type": type,
				"payload": payload
			}
		}

		if msgID && sensorID then
			noop()

		fired {
			ent:messages := ent:messages.defaultsTo({}).put([sensorID, msgID], msg)
		}
	}

	rule handle_seen {
		select when gossip seen where getProcess()

		pre {
			eci = event:attrs{"peer"}{"Rx"}
			msg = event:attrs{"msg"}
		}

		if eci && msg then
			noop()

		fired {
			ent:peerState := ent:peerState.defaultsTo({}).put(eci, msg)
		}
	}

	rule enable_disable_processing {
		select when gossip process

		pre {
			state = event:attrs{"state"}
		}

		if state == "on" || state == "off" then
			noop()

		fired {
			ent:process := state
		}
	}

	rule new_temp {
		select when wovyn new_temperature_reading

		pre {
			time = time:now()
			temp = event:attrs{"temperature"}
			sensorID = getPicoID()
			msgID = <<#{sensorID}:#{ent:sequence}>>

			msg = {
				"messageID": msgID,
				"sensorID": sensorID,
				"timestamp": time,
				"type": "new_temperature_reading",
				"payload": {
					"temperature": temp,
				},
			}
		}

		if msgID && sensorID && time then
			noop()

		fired {
			ent:messages := ent:messages.defaultsTo({}).put([sensorID, msgID], msg)
			ent:sequence := ent:sequence + 1;
		}
	}

	//*******************************************************
	// lab 10 temp violation stuff
	//*******************************************************

	rule toggle_violation_state {
		select when wovyn toggle_violation_state

		pre {
			time = time:now()
			sensorID = getPicoID()
			msgID = <<#{sensorID}:#{ent:sequence}>>
			add = exceedingThreshold() => -1 | 1 // opposite because we are toggling the state

			msg = {
				"messageID": msgID,
				"sensorID": sensorID,
				"timestamp": time,
				"type": "nodes_in_temp_violation",
				"payload": {
					"add": add,
				},
			}
		}

		if msgID && sensorID && time && add then
			noop()

		fired {
			ent:inTempViolation := not exceedingThreshold()
			ent:messages := ent:messages.defaultsTo({}).put([sensorID, msgID], msg)
			ent:sequence := ent:sequence + 1;
		}
	}

	rule pulse_temp_violation {
		select when wovyn pulse_temp_violation

		pre {
			time = time:now()
			sensorID = getPicoID()
			msgID = <<#{sensorID}:#{ent:sequence}>>

			msg = {
				"messageID": msgID,
				"sensorID": sensorID,
				"timestamp": time,
				"type": "nodes_in_temp_violation",
				"payload": {
					"add": 0,
				},
			}
		}

		if msgID && sensorID && time then
			noop()

		fired {
			ent:messages := ent:messages.defaultsTo({}).put([sensorID, msgID], msg)
			ent:sequence := ent:sequence + 1;
		}
	}

    rule clear_everything {
		select when nuke gossip

		pre {
			scheduledID = getSchedule()
		}

		if scheduledID then
			schedule:remove(scheduledID)

		always {
			ent:period := 5 // seconds
			ent:messages := {} // sensorID -> messageID -> message
			ent:peerState :=  {} // eci -> sensorID -> highest seq
			ent:inTempViolation := false
			ent:sequence := 0

			schedule gossip event "heartbeat" repeat << */#{ent:period} * * * * * >> attributes {}
		}
	}
}
