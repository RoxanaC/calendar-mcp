require "mcp"

server = MCP::Server.new(name: "mac-calendar", version: "1.0.0")

def run_applescript(script)
  'osascript' << 'APPLESCRIPT'
#{script}
APPLESCRIPT`.strip
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
  days     = args["days"] || 7
  cal_filter = args["calendar"] ? "whose name is \"#{args["calendar"]}\"" : ""
  script = <<~AS
    set eventList to {}
    set startDate to current date
    set endDate to startDate + (#{days} * days)
    tell application "Calendar"
      repeat with cal in (every calendar #{cal_filter})
        set calEvents to every event of cal whose start date >= startDate and start date <= endDate
        repeat with ev in calEvents
          set evStart to start date of ev as string
          set evEnd to end date of ev as string
          set end of eventList to (evStart & " | " & evEnd & " | " & summary of ev & " [" & name of cal & "]")
        end repeat
      end repeat
    end tell
    return eventList
  AS
  result = run_applescript(script)
  result.empty? ? "No upcoming events found." : result
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
  query = args["query"]
  days  = args["days"] || 30
  script = <<~AS
    set eventList to {}
    set startDate to (current date) - (#{days} * days)
    set endDate to (current date) + (#{days} * days)
    tell application "Calendar"
      repeat with cal in every calendar
        set calEvents to every event of cal whose start date >= startDate and start date <= endDate and summary contains "#{query}"
        repeat with ev in calEvents
          set evStart to start date of ev as string
          set end of eventList to (evStart & " | " & summary of ev & " [" & name of cal & "]")
        end repeat
      end repeat
    end tell
    return eventList
  AS
  result = run_applescript(script)
  result.empty? ? "No events found matching '#{query}'." : result
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
  title    = args["title"]
  start    = args["start"]
  end_time = args["end_time"]
  cal_line   = args["calendar"] ? "set targetCal to first calendar whose name is \"#{args["calendar"]}\"" : "set targetCal to first calendar"
  notes_line = args["notes"]    ? "set description of newEvent to \"#{args["notes"]}\"" : ""
  script = <<~AS
    tell application "Calendar"
      #{cal_line}
      set startDate to date "#{start}"
      set endDate to date "#{end_time}"
      set newEvent to make new event at end of events of targetCal with properties {summary:"#{title}", start date:startDate, end date:endDate}
      #{notes_line}
      save
    end tell
    return "Event '#{title}' created successfully."
  AS
  run_applescript(script)
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
  title = args["title"]
  date  = args["date"]
  script = <<~AS
    tell application "Calendar"
      set targetDate to date "#{date}"
      set startOfDay to targetDate
      set endOfDay to targetDate + 1 * days
      repeat with cal in every calendar
        set matches to every event of cal whose summary is "#{title}" and start date >= startOfDay and start date < endOfDay
        repeat with ev in matches
          delete ev
        end repeat
      end repeat
      save
    end tell
    return "Event '#{title}' deleted."
  AS
  run_applescript(script)
end

transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open