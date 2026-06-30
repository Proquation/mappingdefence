<script>
    export let csdRows = [];
    export let cmaRows = [];
    export let provRows = [];
    export let lqBasis = 'sales';
    export let colourType = 'lq';        // 'lq' | 'totals'
    export let selectedYear;
    export let selectedMode = 'ALL';
    export let selectedGeometry = 'cma'; // 'csd' | 'cma' | 'prov'
    export let formatSales = (v) => `${v}`;

    const lqKey = { sales: 'lq_sales', firms: 'lq_firms', jobs: 'lq_jobs' };

    function absVal(r) {
        if (lqBasis === 'sales') return Number.isFinite(r.total_sales_M) ? r.total_sales_M : null;
        if (lqBasis === 'jobs')  return Number.isFinite(r.total_jobs) ? r.total_jobs : null;
        return r.suppressed ? null : Number(r.n_firms) || null;
    }
    function lqVal(r) {
        const v = r[lqKey[lqBasis]];
        return Number.isFinite(v) ? v : null;
    }
    function rankVal(r) {
        return colourType === 'totals' ? absVal(r) : lqVal(r);
    }
    function fmtAbs(r) {
        const v = absVal(r);
        if (v == null) return '—';
        return lqBasis === 'sales' ? formatSales(v) : v.toLocaleString();
    }

    function firmsVal(r) {
        return r.suppressed ? '<2' : (r.n_firms ?? '—');
    }

    function rank(rows, n) {
        return rows
            .filter(r => r.year === selectedYear && r.NAICS6 === selectedMode && !r.suppressed)
            .filter(r => rankVal(r) != null)
            .sort((a, b) => rankVal(b) - rankVal(a))
            .slice(0, n);
    }

    $: deps = [colourType, lqBasis, selectedYear, selectedMode];

    // pick the active geography's rows + title + how many to show
    $: active = (() => {
        deps;  // dependency
        if (selectedGeometry === 'csd')
            return { title: 'Top 10 census subdivisions', list: rank(csdRows, 10) };
        if (selectedGeometry === 'cma')
            return { title: 'Top 10 census metropolitan areas',
                     list: rank(cmaRows.filter(r => !String(r.region_uid).startsWith('RURAL_')), 10) };
        return { title: 'Provinces & territories', list: rank(provRows, 99) };
    })();

    $: console.log("selectedGeometry:", selectedGeometry);

    $: metricLabel = lqBasis === 'sales' ? 'Sales' : lqBasis === 'jobs' ? 'Jobs' : 'Firms';

    $: valueLabel = colourType === 'totals'
        ? (lqBasis === 'sales' ? 'Sales' : lqBasis === 'jobs' ? 'Jobs' : 'Firms')
        : `LQ (${lqBasis})`;
</script>

<div class="rankings">
    <div class="rank-col">
        <h4>{active.title}</h4>
        <!-- <div style="color:red">DEBUG geom={selectedGeometry}</div> -->
        <table>
            <thead>
                <tr>
                    <th class="rk">#</th>
                    <th>Region</th>
                    <th class="num">{metricLabel}</th>
                    <th class="num">Firms</th>
                    {#if colourType !== 'totals'}<th class="num">LQ ({lqBasis})</th>{/if}
                </tr>
            </thead>
            <tbody>
                {#each active.list as r, i}
                    <tr>
                        <td class="rk">{i + 1}</td>
                        <td class="name">{r.region_name}</td>
                        <td class="num">{fmtAbs(r)}</td>
                        <td class="num">{firmsVal(r)}</td>
                        {#if colourType !== 'totals'}
                            <td class="num">{Number.isFinite(lqVal(r)) ? lqVal(r).toFixed(2) + '×' : '—'}</td>
                        {/if}
                    </tr>
                {:else}
                    <tr><td colspan={colourType === 'totals' ? 4 : 5} class="empty">No data for this selection</td></tr>
                {/each}
            </tbody>
        </table>
    </div>
</div>

<style>
    .rankings { max-width: 680px; margin: 24px auto 0; font-family: OpenSans; }
    .rank-col h4 { width: 680px; font-family: OpenSansBold; font-size: 14px; color: var(--brandWhite);}
    table { width: 100%; border-collapse: collapse; font-size: 12px; color: var(--brandWhite); }
    th, td { padding: 4px 6px; text-align: left; border-bottom: 1px solid rgba(255,255,255,0.1); }
    th { font-family: OpenSansBold; color: rgba(255,255,255,0.6); font-size: 11px; }
    .rk { width: 22px; color: rgba(255,255,255,0.5); }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .name { max-width: 680px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .empty { color: rgba(255,255,255,0.4); font-style: italic; }
</style>