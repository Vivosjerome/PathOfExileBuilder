-- Frozen Benchmark A/B/C/D. Do not recompute; do not overwrite the JSON snapshots.

return {
	BENCHMARKS = {
		{
			id = "A",
			label = "Uniques only, no resist constraint",
			file = "docs/benchmarks/A-uniques-unconstrained.json",
			dps = 482651.55,
			epsilon = 1,
		},
		{
			id = "B",
			label = "Uniques only, 75/75/75",
			file = "docs/benchmarks/B-uniques-75res.json",
			dps = 96974.903302893,
			epsilon = 1,
		},
		{
			id = "C",
			label = "Uniques + rares, 75/75/75",
			file = "docs/benchmarks/C-uniques-rares-75res.json",
			dps = 197639.86666667,
			epsilon = 1,
		},
		{
			id = "D",
			label = "Uniques + rares + classic jewels, 75/75/75",
			file = "docs/benchmarks/D-uniques-rares-jewels-75res.json",
			dps = 246276.004,
			epsilon = 1,
		},
	},
}
