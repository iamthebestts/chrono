local runStep = require("../scripts/processExecution").runStep

runStep("sourcemap", {
	"rojo",
	"sourcemap",
	"test.project.json",
	"-o",
	"sourcemap.json",
})

runStep("Selene check", { "selene", "src" })

runStep("Style check", { "stylua", "-c", "src" })

runStep("Type check", {
	"luau-lsp",
	"analyze",
	"--defs=globalTypes.d.luau",
	"--sourcemap=sourcemap.json",
	"--ignore=DevPackages/**",
	"src",
})
