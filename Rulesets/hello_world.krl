ruleset hello_world {
  meta {
  name "Hello World"
  description <<
The first ruleset for the Quickstart
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
}
