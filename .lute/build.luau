local runStep = require("../scripts/processExecution").runStep

runStep("sourcemap", {
	"rojo",
	"sourcemap",
	"default.project.json",
	"-o",
	"sourcemap.json",
})

runStep(
	"Fetch types",
	{ "curl", "-s", "-O", "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/master/scripts/globalTypes.d.luau" }
)

runStep("Selene check", { "selene", "src" })
runStep("Style format", { "stylua", "src" })

runStep("build", {
	"rojo",
	"build",
	"default.project.json",
	"-o",
	"lux.rbxm",
})
