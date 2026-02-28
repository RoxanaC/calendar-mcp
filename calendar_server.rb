require "mcp"
require "json"
require "shellwords"

server = MCP::Server.new(name: "mac-calendar", version: "1.0.0")

HELPER_PATH = File.join(__dir__, "calendar_helper")

def run_swift_helper(subcommand, params = {})
  json = JSON.generate(params)
  `#{Shellwords.escape(HELPER_PATH)} #{subcommand} #{Shellwords.escape(json)} 2>/dev/null`.strip
end

server.define_tool(
  name: "get_upcoming_events",
  description: "Get upcoming calendar events from macOS Calendar",
  input_schema: {
    type: "object",
    properties: {
      days:     { type: "integer", description: "Number of days ahead to look (default: 7)" },
      calendar: { type: "string",  description: "Calendar name to filter by (optional)" }
    }
  }
) do |args|
  result = run_swift_helper("get_upcoming_events", {
    days:     args[:days] || 7,
    calendar: args[:calendar]
  }.compact)
  MCP::Tool::Response.new([{ type: "text", text: result.empty? ? "No upcoming events found." : result }])
end

server.define_tool(
  name: "search_events",
  description: "Search macOS Calendar events by keyword",
  input_schema: {
    type: "object",
    properties: {
      query: { type: "string",  description: "Keyword to search for in event titles" },
      days:  { type: "integer", description: "Days back and forward to search (default: 30)" }
    },
    required: ["query"]
  }
) do |args|
  query = args[:query]
  result = run_swift_helper("search_events", {
    query: query,
    days:  args[:days] || 30
  })
  MCP::Tool::Response.new([{ type: "text", text: result.empty? ? "No events found matching '#{query}'." : result }])
end

server.define_tool(
  name: "create_event",
  description: "Create a new event in macOS Calendar",
  input_schema: {
    type: "object",
    properties: {
      title:    { type: "string", description: "Event title" },
      start:    { type: "string", description: "Start datetime e.g. '2026-03-01 14:00'" },
      end_time: { type: "string", description: "End datetime e.g. '2026-03-01 15:00'" },
      calendar: { type: "string", description: "Calendar name (optional)" },
      notes:    { type: "string", description: "Optional notes" }
    },
    required: ["title", "start", "end_time"]
  }
) do |args|
  result = run_swift_helper("create_event", {
    title:    args[:title],
    start:    args[:start],
    end_time: args[:end_time],
    calendar: args[:calendar],
    notes:    args[:notes]
  }.compact)
  MCP::Tool::Response.new([{ type: "text", text: result }])
end

server.define_tool(
  name: "delete_event",
  description: "Delete a calendar event by title and date",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "Exact title of the event to delete" },
      date:  { type: "string", description: "Date of the event e.g. '2026-03-01'" }
    },
    required: ["title", "date"]
  }
) do |args|
  result = run_swift_helper("delete_event", {
    title: args[:title],
    date:  args[:date]
  })
  MCP::Tool::Response.new([{ type: "text", text: result }])
end

transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
