# LogSink: SavedVariables

A simple sink for [LibLog-1.0](https://github.com/Snakybo/LibLog-1.0) that captures the logging stream and persists it in saved variables, per session.

## Limitations

* Logs persist through reloads, but not throughout logouts, every login clears the existing data.
* Logs are capped to the most recent 1000 logs per addon, to prevent the saved variables from exploding.

## API

This sink provides an external API which can be used by other addons or sinks to restore their log stream upon reload.

To use this, add this sink to your `OptionalDeps`, afterwards you can do:

```lua
if LogSinkSavedVariables ~= nil then
	LogSinkSavedVariables:GetBufferWhenAvailable(function(buffer)
		-- buffer: LibLog-1.0.LogMessage[]
	end)
end
```
