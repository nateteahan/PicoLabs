ruleset twilio_module {
    meta {
        name "Twilio Module"
        description <<
            The module containing the actions and keys to use Twilio
        >>
        logging on
        configure using
            apiKey = ""
            sessionId = ""
            number = ""
        author "Nate Teahan"
        provides messages, filterMessages, sendMessage
    }

    global {
        url = "https://api.twilio.com/2010-04-01"
        authentication = {"session": sessionId, "password": apiKey}

        messages = function() {
            http:get(<<#{url}/Accounts/#{sessionId}/Messages.json>>, auth=authentication){"content"}.decode()
        }

        filterMessages = function(filter) {
            http:get(<<#{url}/#{sessionId}/Messages.json>>, auth=authentication, qs=filter) {"content"}.decode().klog("Filtered messages:")
        }

        sendMessage = defaction(phoneNumber, messageBody) {
            messageString = {"To": phoneNumber, "From": number, "Body": messageBody}
            http:post(<<#{url}/Accounts/#{sessionId}/Messages.json>>, form=messageString, auth=authentication) setting(response)
            return response{"content"}.decode()
        }
    }

}
