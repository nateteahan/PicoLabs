ruleset twilio {
	meta {
		name "Twilio"
		author "Nate Teahan"

		configure using
			accountSID = ""
			authToken = ""

		provides sendSMS, messages
	}

	global {
		baseURL = <<https://api.twilio.com/2010-04-01/Accounts/#{accountSID}>>

		sendSMS = defaction(from, to, message) {
			http:post((baseURL+"/Messages.json").klog("url"), auth = {
				"username": accountSID,
				"password": authToken
			}.klog("auth"), form = {
				"From": from,
				"To": to,
				"Body": message
			}.klog("form")) setting(resp)

			return resp{"content"}.decode()
		}

		messages = function(from, to, pageSize) {
			qs = {
				"From": from,
				"To": to,
				"PageSize": pageSize
			}

			resp = http:get((baseURL+"/Messages.json").klog("url"), auth = {
				"username": accountSID,
				"password": authToken
			}.klog("auth"), qs = qs.filter(function(v, k) {v}).klog("query"))

			resp{"content"}.decode()
		}
	}
}