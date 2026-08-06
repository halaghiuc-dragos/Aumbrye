extends RefCounted
class_name ValidationRunnerOptions

var suite_filter: PackedStringArray = []
var test_prefix: String = ""
var shuffle: bool = false
var seed: int = 0
var repeat_count: int = 1
var fail_fast: bool = false
var verbose: bool = false
var report_json_path: String = "user://mcp_validation.json"
var report_junit_path: String = "user://mcp_validation.xml"
var harness_fast_timeout: bool = false


static func from_cmdline() -> ValidationRunnerOptions:
	var options := ValidationRunnerOptions.new()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			var raw := arg.substr("--suite=".length())
			for part in raw.split(",", false):
				var name := part.strip_edges()
				if name != "":
					options.suite_filter.append(name)
		elif arg.begins_with("--test="):
			options.test_prefix = arg.substr("--test=".length()).strip_edges()
		elif arg == "--shuffle":
			options.shuffle = true
		elif arg.begins_with("--seed="):
			options.seed = int(arg.substr("--seed=".length()))
		elif arg.begins_with("--repeat="):
			options.repeat_count = maxi(1, int(arg.substr("--repeat=".length())))
		elif arg == "--fail-fast":
			options.fail_fast = true
		elif arg == "--verbose":
			options.verbose = true
		elif arg.begins_with("--report="):
			var report_path := arg.substr("--report=".length()).strip_edges()
			options.report_json_path = report_path
			options.report_junit_path = report_path.get_basename() + ".xml"
		elif arg == "--harness-fast-timeout":
			options.harness_fast_timeout = true
	return options
