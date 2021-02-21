function get_temp() {
    var eci = "ckl7f4xxa0018u8rv5ubh9lgt";
    var endpoint = "http://localhost:3000/sky/cloud/" + eci + "/temperature_store/inrange_temperatures";

    fetch(endpoint).then((response) => {
        return response.json();
    }).then((test)=> {
        var current_temp = test[test.length - 1]
        current_temp = current_temp.temperature
        document.getElementById("current_temp").innerHTML = current_temp;

        // Get the 20 most recent temperatures
        var i, recents = "";
        if (test.length > 20) {
            for (i = test.length - 20; i  < test.length; i++) {
                recents += test[i].temperature + "<br>"
            }
        }
        else {
            for (i = 0; i  < test.length; i++) {
                recents += test[i].temperature + "<br>"
            }
        }
        document.getElementById("recent_temps").innerHTML = recents;
        var threshold_endpoint = "http://localhost:3000/sky/cloud/" + eci + "/temperature_store/threshold_violations"
        return fetch(threshold_endpoint);
    }).then((results) => {
        return results.json();
    }).then((myJson) => {
        console.log("myJson", myJson);

        var i, threshold = ""

        for (i = 0; i < myJson.length; i++) {
            threshold += myJson[i].violation + "<br>"
        }

        document.getElementById("thresholds").innerHTML = threshold;
    })
    
}

function get_values() {
    var eci = "ckl7f4xxa0018u8rv5ubh9lgt";
    var endpoint = "http://localhost:3000/sky/cloud/" + eci + "/sensor_profile/get_data";

    fetch(endpoint).then((response) => {
        return response.json();
    }).then((myJson) => {
        console.log("myJson", myJson);

        var location, name, curr_threshold, number = "";
        location = myJson["location"]
        name = myJson["name"]
        curr_threshold = myJson["threshold"]
        number = myJson["sms_number"]

        document.getElementById("name").placeholder = name;
        document.getElementById("location").placeholder = location;
        document.getElementById("number").placeholder = number;
        document.getElementById("threshold").placeholder = curr_threshold;
    })
}

function update_values() {
    var name = document.getElementById("name").value
    var location = document.getElementById("location").value
    var sms = document.getElementById("number").value
    var threshold = document.getElementById("threshold").value

    var eci = "ckl7f4xxa0018u8rv5ubh9lgt";
    var eid = "lab5"
    var endpoint = "http://localhost:3000/sky/event/" + eci + "/" + eid + "/sensor/profile_updated";
    endpoint += "?location=" + location + "&"
            + "name=" + name + "&"
            + "threshold=" + threshold + "&"
            + "sms=" + sms

    fetch(endpoint).then((response) => {
        return response
    })
}