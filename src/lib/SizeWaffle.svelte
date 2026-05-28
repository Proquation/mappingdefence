<script>
    export let items = []; // data items like value, label, color
    export let total = 0; // sum of all values
    export let minSquares = 1; // minimum squares any positive value gets

    const squareCount = 100;

    function toColor(value) {
        if (!value) return 'var(--brandGray)';
        return value.startsWith('--') ? `var(${value})` : value;
    }

    function allocateSquares(values, totalValue) {
        // empty data handling
        if (!values.length || totalValue <= 0) {
            return Array.from({ length: squareCount }, () => ({
                color: 'var(--brandGray)',
                label: 'No data'
            }));
        }

        // initialize items
        const prepared = values.map((item, index) => {
            // raw number of squares
            const raw = (item.value / totalValue) * squareCount;
            const floored = Math.floor(raw);
            const base = item.value > 0 ? Math.max(minSquares, floored) : 0;
            return {
                index,
                label: item.label,
                color: toColor(item.color),
                value: item.value,
                displayValue: item.displayValue,
                raw,
                remainder: raw - floored,
                count: base,
                min: item.value > 0 ? minSquares : 0
            };
        });

        // leftover square handling -> how many are left to distribute after flooring the actual data
        let used = prepared.reduce((sum, item) => sum + item.count, 0);
        let leftover = squareCount - used;

        // highest remainders get the extra square
        if (leftover > 0) {
            const ranked = [...prepared].sort((a, b) => b.remainder - a.remainder || a.index - b.index);
            for (let i = 0; i < leftover; i += 1) {
                ranked[i % ranked.length].count += 1;
            }
        }

        // if the minimum squares caused to overshoot (min squares > 1), then remove based on the rank (lowest remained)
        // recall remainder is leftover after flooring the proportion
        // if (leftover < 0) {
        //     let toRemove = Math.abs(leftover);
        //     const ranked = [...prepared]
        //         .filter((item) => item.count > item.min)
        //         .sort((a, b) => a.remainder - b.remainder || b.count - a.count); // remove lowest remainder first then remove higher count to distribute more evenly

        //     let pointer = 0;
        //     while (toRemove > 0 && ranked.length > 0) {
        //         const target = ranked[pointer % ranked.length];
        //         if (target.count > target.min) {
        //             target.count -= 1;
        //             toRemove -= 1;
        //         }
        //         pointer += 1;
        //     }
        // }

        // building the square array using 
        const squares = [];
        prepared.forEach((item) => {
            for (let i = 0; i < item.count; i += 1) {
                squares.push({ color: item.color, label: item.label, value: item.value, displayValue: item.displayValue });
            }
        });

        while (squares.length < squareCount) {
            squares.push({ color: 'var(--brandGray)', label: 'No data', value: 'No data' });
        }

        return squares.slice(0, squareCount);
    }

    $: squares = allocateSquares(items, total);
</script>

<div class="waffle-grid" role="img" aria-label="Waffle chart showing company size distribution">
    {#each squares as square}
        <span
            class="waffle-cell"
            style="background-color: {square.color}"
            title="{square.label}: {square.displayValue}"
        ></span>
    {/each}
</div>

<style>
    .waffle-grid {
        display: grid;
        grid-template-columns: repeat(10, 1fr);
        gap: 4px;
        width: 100%;
        max-width: 360px;
        margin: 0 auto;
        margin-top: 10px;
        margin-bottom: 10px;
    }

    .waffle-cell {
        aspect-ratio: 1 / 1;
        border-radius: 3px;
        border: 1px solid var(--brandGray);
        background-color: var(--brandGray);
    }
</style>
