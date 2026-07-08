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
                {#if colourType !== 'totals'}<th class="num">LQ ({lqBasis})</th>{/if}
                <th class="num">{metricLabel}</th>
                <th class="num">Firms</th>
            </tr>
        </thead>
        <tbody>
            {#each active.list as r, i}
                <tr>
                    <td class="rk">{i + 1}</td>
                    <td class="name">{r.region_name}</td>
                    {#if colourType !== 'totals'}
                        <td class="num">{Number.isFinite(lqVal(r)) ? lqVal(r).toFixed(2) + '×' : '—'}</td>
                    {/if}
                    <td class="num">{fmtAbs(r)}</td>
                    <td class="num">{firmsVal(r)}</td>
                </tr>
            {:else}
                <tr><td colspan={colourType === 'totals' ? 4 : 5} class="empty">No data for this selection</td></tr>
            {/each}
        </tbody>
        </table>
    </div>
</div>

<style>
    .rankings { width: 680px; margin: 24px auto 0; font-family: OpenSans; }
    .rank-col h4 { font-family: OpenSansBold; font-size: 13px; color: var(--brandWhite); margin-bottom: 8px; width: 100%;}
    table { width: 100%; border-collapse: collapse; font-size: 12px; color: var(--brandWhite); }
    th { text-align: left; font-family: OpenSansBold; padding: 6px 8px;
        border-bottom: 1px solid rgba(255,255,255,0.2); font-size: 11px; }
    td { padding: 5px 8px; border-bottom: 1px solid rgba(255,255,255,0.08); }
    th.num, td.num { text-align: right; font-variant-numeric: tabular-nums; }
    .rk { width: 28px; color: rgba(255,255,255,0.5); }
    .name { max-width: 400px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .empty { color: rgba(255,255,255,0.4); font-style: italic; }
    tr:hover td { background: rgba(255,255,255,0.04); }
</style>