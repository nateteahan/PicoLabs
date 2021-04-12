ruleset gossip {
    meta {
		use module io.picolabs.subscription alias subscription

		shares getCurrentPeerState, getProcess, getSequenceNumber, getPicoID, getMissingMessages, getPeer, getHighestSequenceNumber, instantiateMessage, generateMessageID,
        prepareMessage, getSeenMessage, getRumorMessage, getSchedule, tempLogs
	}

    global {
        // Functions
        getSchedule = function() {
            ent:schedule
        }

        getProcess = function() {
            ent:process
        }

        tempLogs = function() {
            ent:seen_messages.filter(function(a) {
                messageID = a{"MessageID"};
                sequence_number = getSequenceNumber(messageID);
                picoID = getPicoID(messageID);

                ent:seen{picoID} == sequence_number
            });
        }

        getCurrentPeerState = function() {
            ent:current_peer_state
        }

        getHighestSequenceNumber = function(id) {
            filtered_seen = ent:seen_messages.filter(function(a) {
                pico_ID = getPicoID(a{"MessageID"});
                pico_ID == id
            }).map(function(a){getSequenceNumber(a{"MessageID"})})

            sorted_seen = filtered_seen.sort(function(primary, secondary) {
                primary < secondary => -1 |
                primary == secondary => 0 |
                1
            })

            sorted_seen.reduce(function(primary, secondary) {
                secondary == primary + 1 => secondary | primary
            }, -1)
        }

        instantiateMessage = function(temperature, timestamp) {
            {
                "MessageID": generateMessageID(),
                "SensorID": meta:picoId,
                "Temperature": temperature,
                "Timestamp": timestamp
            }
        }

        generateMessageID = function() {
            sequence_number = ent:current_sequence
            <<#{meta:picoId}:#{sequence_number}>>
        }

        prepareMessage = function(neighbor) {
            coin_flip = random:integer(1)
            message_type = (coin_flip == 0) => getRumorMessage(neighbor) | getSeenMessage()
            message_type
        }

        getSequenceNumber = function(id) {
            message_elements = id.split(re#:#)
            message_elements[message_elements.length() - 1].as("Number")
        }

        getPicoID = function(id) {
            message_elements = id.split(re#:#)
            message_elements[0]
        }

        getMissingMessages = function(seen_message) {
            ent:seen_messages.klog("seen_messages").filter(function(a) { 
                origin_id = getPicoID(a{"MessageID"})
                keep_message = seen_message{origin_id}.isnull() || (seen_message{origin_id} < getSequenceNumber(a{"MessageID"})) => true | false
                keep_message
            }).sort(function(a,b) {
                primary_sequence = getSequenceNumber(a{"MessageID"})
                secondary_sequence = getSequenceNumber(b{"MessageID"})
                primary_sequence < secondary_sequence => -1 |
                primary_sequence == secondary_sequence => 0 | 
                1
            })
        }

        getPeer = function() {
            subscribers = subscription:established("Rx_role", "gossip_node").klog("Subscribers")
            random_sub = random:integer(subscribers.length() - 1)

            current_peers = ent:current_peer_state
            filtered_peers = current_peers.filter(function(v,k) {
                getMissingMessages(v).length() > 0
            }).klog("FILTERED MESSAGES")

            random = random:integer(filtered_peers.length() - 1).klog("RANDOM PEER:")
            item = filtered_peers.keys()[random].klog("ITEM:")
            subscribers.filter(function(a){a{"Tx"} == item})[0].klog("Final:").isnull() => subscribers[random_sub] | subscribers.filter(function(a){a{"Tx"} == item})[0]
        }

        getSeenMessage = function() {
            {
                "message" : ent:seen,
                "message_type" : "seen_message"
            }
        }

        getRumorMessage = function(subscriber) {
            missing_messages = getMissingMessages(ent:current_peer_state{subscriber{"Tx"}}).klog("Missing messages:")
            rumor_message = {
                "message": missing_messages.length() == 0 => null | missing_messages[0],
                "message_type": "rumor_message"
            }
            rumor_message
        }
    }

    // Rules
    rule update_process {
        select when gossip update_process

        pre {
            new_process = event:attrs{"updated_process"}
        }
        always {
            ent:process := new_process

            // Notify subscribers that gossip is up and running again
            raise gossip event "gossip_running" if (new_process == "on")
        }
    }

    rule gossip_heartbeat {
        select when gossip heartbeat where ent:process == "on"

        pre {
            neighbor = getPeer().klog("Sending to:")
            message = prepareMessage(neighbor).klog("message is:")
        }

        if (not neighbor.isnull()) && (not message{"message"}.isnull()) then
            noop()

        fired {
            raise gossip event "send_rumor_message" attributes {
                "neighbor": neighbor,
                "message": message{"message"}.klog("Message being sent to send_rumor rule")
            }
            if (message{"message_type"} == "rumor_message")

            raise gossip event "send_seen_message" attributes {
                "neighbor": neighbor,
                "message": message{"message"}
            }
            if (message{"message_type"} == "seen_message")
        }
    }

    rule send_rumor_message {
        select when gossip send_rumor_message
        pre {
            neighbor = event:attrs{"neighbor"}.klog("This is the neighbor receiving the rumor message")
            message = event:attrs{"message"}.klog("This is the message being sent as a rumor:")
            message_id = getPicoID(message{"MessageID"})
            sequence_number = getSequenceNumber(message{"MessageID"})
        }

        event:send({
            "eci": neighbor{"Tx"},
            "eid": "gossip_rumor_message",
            "domain": "gossip",
            "type": "rumor",
            "attrs": {"message": message}
        })

        // Update our peers
        always {
            ent:current_peer_state{[neighbor{"Tx"}, message_id]} := sequence_number
            if (ent:current_peer_state{neighbor{"Tx"}}{message_id} + 1 == sequence_number) || (ent:current_peer_state{neighbor{"Tx"}}{message_id}.isnull() && sequence_number == 0)
        }
    }

    rule send_seen_message {
        select when gossip send_seen_message
        pre {
            neighbor = event:attrs{"neighbor"}.klog("Neighbor:")
            message = event:attrs{"message"}.klog("Seen message:")
        }

        event:send({
            "eci": neighbor{"Tx"},
            "eid": "gossip_seen_message",
            "domain": "gossip",
            "type": "seen_message",
            "attrs": {"message": message, "sent_from": {"PicoID": meta:picoId, "Rx": neighbor{"Rx"}}}
        })
    }

    rule gossip_rumor {
        select when gossip rumor where ent:process == "on"
        
        pre {
            attr = event:attrs.klog("This is the event attr map")
            message_id = event:attrs{"message"}{"MessageID"}.klog("MESSAGE ID:")
            sequence_number = getSequenceNumber(message_id).klog("SEQUENCE NUMBER:")
            pico_ID = getPicoID(message_id).klog("PICO ID:")
            seen_msg = ent:seen{pico_ID}.klog("SEEN MESSAGE:")
            first_neighbor = ent:seen{pico_ID}.isnull().klog("FIRST NEIGHBOR:")
        }

        if first_neighbor then 
            noop()

        fired {
            ent:seen{pico_ID} := -1
        } finally {
            ent:seen_messages := ent:seen_messages.append({
                "MessageID": message_id,
                "SensorID": event:attrs{"SensorID"},
                "Temperature": event:attrs{"Temperature"},
                "Timestamp": event:attrs{"Timestamp"}
            })
            if (ent:seen_messages.filter(function(a) {a{"MessageID"} == message_id}).length() == 0)

            raise gossip event "update_sequence_number" attributes {
                "PicoID": pico_ID,
                "sequence_number": sequence_number
            }
        }
    }

    rule update_sequence_number {
        select when gossip update_sequence_number
        pre {
            attrs = event:attrs.klog("Event attrs coming to update sequence number:")
            pico_ID = event:attrs{"PicoID"}
            sequence_number = event:attrs{"sequence_number"}
        }

        always {
            ent:seen{pico_ID} := getHighestSequenceNumber(pico_ID)
        }
    }

    rule save_seen {
        select when gossip seen_message

        pre {
            send_channel = event:attrs{"send_channel"}{"Rx"}
            message = event:attrs{"message"}
        }

        always {
            ent:current_peer_state{send_channel} := message
        }
    }

    rule return_missing_messages {
        select when gossip seen_message where ent:process == "on"
        foreach getMissingMessages(event:attrs{"message"}) setting(msg)
        pre {
            send_channel_ID = event:attrs{"send_channel"}{"PicoID"}
            rx = event:attrs{"send_channel"}{"Rx"}
        }

        event:send({
            "eci": rx,
            "eid": "gossip_seen_message_response",
            "domain": "gossip",
            "type": "rumor",
            "attrs": msg
        })
    }

    rule toggle_process {
        select when gossip toggle_process     
        pre {
            state = ent:process
        }       
        always {
            ent:process := state == "on" => "off" | "on"
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            Tx = event:attrs{"Tx"}.klog("Tx: ")
        }
        if not Tx.isnull() then noop()
        fired {
            raise wrangler event "pending_subscription_approval"
            attributes event:attrs;

            ent:current_peer_state{Tx} := {}
        }
    }

    rule added_subscriber {
        select when wrangler subscription_added
        pre {
            Tx = event:attrs{"_Tx"}.klog("_Tx: ")
        }
        if not Tx.isnull() then noop()
        fired {
            ent:current_peer_state{Tx} := {}
        }
    }

    rule received_temp_reading {
        select when wovyn new_temperature_reading

        pre {
            temperature = event:attrs{"temperature"}
            timestamp = event:attrs{"timestamp"}
            message = instantiateMessage(temperature, timestamp)
        }

        always {
            ent:seen_messages := ent:seen_messages.append(message.klog("Message Value:"))
            ent:seen{meta:picoId} :=  getHighestSequenceNumber(meta:picoId)
            ent:current_sequence := ent:current_sequence + 1
        }
    }

    rule ruleset_added {
        select when wrangler ruleset_added where event:attrs{"rids"} >< meta:rid

        always {
            ent:schedule := 3
            ent:current_sequence := 0;
            ent:seen := {};
            ent:current_peer_state := {};
            ent:seen_messages := [];
            ent:process := "on";
            raise gossip event "heartbeat" attributes {"schedule": ent:schedule}
        }
    }

    rule fire_gossip_schedule {
        select when gossip heartbeat
        pre {
            timeframe = ent:schedule.klog("ent:schedule:")
        }

        always {
            schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": timeframe})
        }
    }

    rule change_gossip_schedule {
        select when gossip change_gossip_schedule
        pre {
            new_schedule = event:attrs{"schedule"}.defaultsTo(ent:schedule).klog("Schedule")
        }
        always {
            ent:schedule := new_schedule
        }
    }

    rule clear_everything {
        select when nuke gossip
        always {
            ent:schedule := 8
            ent:current_sequence := 0;
            ent:seen := {};
            ent:current_peer_state := {};
            ent:seen_messages := [];
            ent:process := "on";
        }
    }
}
