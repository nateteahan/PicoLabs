ruleset use_twilio {
    meta {
        use module twilio_module alias twilio
        with
            apiKey = meta:rulesetConfig{"apiKey"}
            sessionId = meta:rulesetConfig{"sessionId"}
            number = meta:rulesetConfig{"number"}
        shares retrieveMessages
    }

    global {
        retrieveMessages = function(filter) {
            filter.isnull() => twilio:messages() | twilio:filterMessages(filter)
        }
    }

    rule send_message {
        select when twilio send_message
        pre {
            message = event:attrs{"message"}
            phoneNumber = event:attrs{"phoneNumber"}
        }
        if message && phoneNumber then 
            twilio:send_message(phoneNumber, message) setting(response)
    }
}
