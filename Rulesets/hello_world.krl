ruleset echo_monkey {
    meta {
      name "Hello World"
      description <<
        A first ruleset for the Quickstart
      >>
      author "Nate Teahan"
      logging on
      shares hello
    }
  
    global {
      hello = function(obj) {
        msg = "Hello " + obj;
        msg
      }
    }
  
    rule hello_world {
      select when echo hello
      send_directive("say", {"something": "Hello World"})
    }

 
  rule echo_monkey_one {
    select when echo monkey_one
    pre {
      name = event:attrs{"name"}.defaultsTo("monkey").klog();
      greeting = "Hello, " + name;
    }
    send_directive("say", {"something": greeting})
  }

  rule echo_monke_two {
    select when echo monkey_two
    pre {
      name = event:attrs{"name"} => event:attrs{"name"} | "monkey";
      greeting = "Hello, " + name;
    }
    send_directive("say", {"something": greeting})
  }
}
