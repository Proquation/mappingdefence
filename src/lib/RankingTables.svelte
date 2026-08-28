<script>

    import { slide } from 'svelte/transition';

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

    let expanded = false;

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

    $: deps = [colourType, lqBasis, selectedYear, selectedMode, selectedGeometry];

    $: { deps; expanded = false; }

    // pick the active geography's rows + title + how many to show
    $: active = (() => {
        deps;  // dependency
        if (selectedGeometry === 'csd')
            return { title: 'Census Subdivisions', list: rank(csdRows, 25), expandable: true };
        if (selectedGeometry === 'cma')
            return { title: 'Census Metropolitan Areas',
                     list: rank(cmaRows.filter(r => !String(r.region_uid).startsWith('RURAL_')), 25),
                     expandable: true };
        return { title: 'Provinces & territories', list: rank(provRows, 99), expandable: false };
    })();

    $: tenList = active.list.slice(0, 10);
    $: twentyfiveList = active.list.slice(10, 25);

    $: displayTitle = active.expandable
        ? `Top ${expanded ? Math.min(25, active.list.length) : Math.min(10, active.list.length)} ${active.title}`
        : active.title;

    $: console.log("selectedGeometry:", selectedGeometry);

    $: metricLabel = lqBasis === 'sales' ? 'Sales' : lqBasis === 'jobs' ? 'Jobs' : 'Firms';

    $: valueLabel = colourType === 'totals'
        ? (lqBasis === 'sales' ? 'Sales' : lqBasis === 'jobs' ? 'Jobs' : 'Firms')
        : `LQ (${lqBasis})`;
</script>

<div class="rankings">
    <div class="rank-col">
        <h4>{displayTitle}</h4>
        <table>
            <thead>
                <tr>
                    <th class = "rk">#</th>
                    <th>Region</th>
                    {#if colourType !== 'totals'}<th class = "num">LQ ({lqBasis})</th>{/if}
                    <th class = "num">{metricLabel}</th>
                </tr>
            </thead>

            <tbody>
                {#each tenList as r, i}
                    <tr>
                        <td class="rk">{i + 1}</td>
                        <td class="name">{r.region_name}</td>
                        {#if colourType !== 'totals'}
                            <td class="num">{Number.isFinite(lqVal(r)) ? lqVal(r).toFixed(2) : '—'}</td>
                        {/if}
                        <td class="num">{fmtAbs(r)}</td>
                    </tr>
                {:else}
                    <tr><td colspan={colourType === 'totals' ? 4 : 5} class="empty">No data for this selection</td></tr>
                {/each}

                {#if expanded}
                    {#each twentyfiveList as r, i (r.region_uid)}
                        <tr transition:slide={{ duration: 200 }}>
                            <td class="rk">{i + 11}</td>
                            <td class="name">{r.region_name}</td>
                            {#if colourType !== 'totals'}
                                <td class="num">{Number.isFinite(lqVal(r)) ? lqVal(r).toFixed(2) : '—'}</td>
                            {/if}
                            <td class="num">{fmtAbs(r)}</td>
                        </tr>
                    {/each}
                {/if}
            </tbody>
        </table>

        {#if active.expandable && twentyfiveList.length > 0}
            <button class="expand-btn" on:click={() => (expanded = !expanded)}>
                {expanded ? 'Show top 10' : `Show up to Top 25`}
            </button>
        {/if}
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
    .expand-btn {
        display: block;
        margin: 10px auto 0;
        padding: 4px 12px;
        border: 1px solid var(--brandWhite);
        border-radius: 3px;
        background: transparent;
        color: var(--brandWhite);
        font-family: OpenSans;
        font-size: 12px;
        cursor: pointer;
    }
    .expand-btn:hover { background: rgba(255,255,255,0.08); }
</style>