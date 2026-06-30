<script>
	import { onDestroy, onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';

	import maplibregl from 'maplibre-gl';
	import { Protocol } from 'pmtiles';
	import { base } from '$app/paths';

	// register pmtiles:// protocol once, before creating the map
	const protocol = new Protocol();
	maplibregl.addProtocol('pmtiles', protocol.tile);

	const SOURCE_ID = 'csd';
	const SRC_LAYER = 'csd';          // MUST match tippecanoe --layer=csd
	const FILL_LAYER = 'csd-fill';

	
	export let geojson = null;
	export let recordByUid = {};
	export let formatSales = (v) => `${v}`;
	export let lqBasis = 'sales';
	export let colourType = 'lq';
	export let provinceGeojson = null;
	const SEQ_LO = '#1a2a4a', SEQ_HI = '#4db8ff';   // sequential dark→blue for totals	

	let map, mapContainer, mapLoaded = false, popup;

	// const SOURCE_ID = 'regions';
	// const FILL_LAYER = 'region-fill';
	const LINE_LAYER = 'region-line';

	let UNDER = '#ff6b4a';
	let MID   = '#CCCCCC';
	let OVER  = '#4db8ff';

	const DARK_STYLE = {
		version: 8,
		glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
		sources: {},
		layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#333333' } }]
	};

	$: absClamp = (() => {
		const vals = Object.values(recordByUid).map((r) => r.absVal).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 1;
		return vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1];
	})();

	$: lqClamp = (() => {
		const vals = Object.values(recordByUid).map((r) => r.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(1, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	$: totalMetric = (() => {
		const vals = Object.values(recordByUid);
		if (lqBasis === 'sales') return vals.map((r) => r.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return vals.map((r) => r.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return vals.map((r) => Number(r.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: lqMin = (() => {
    const vals = Object.values(recordByUid).map(r => r.lq).filter(Number.isFinite);
    return vals.length ? Math.min(...vals) : 0;
	})();

	$: lqMax = (() => {
		const vals = Object.values(recordByUid).map(r => r.lq).filter(Number.isFinite);
		return vals.length ? Math.max(...vals) : 3;
	})();

	$: midPct = (() => {
    	if (lqMax === lqMin) return 50;
		return ((1 - lqMin) / (lqMax - lqMin) * 100).toFixed(1);
	})();

	$: totalLabel   = lqBasis === 'sales' ? 'Total sales (shown)' : lqBasis === 'jobs' ? 'Total jobs (shown)' : 'Total firms (shown)';
	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric) : totalMetric.toLocaleString();

	function enrichGeojson(gj, lookup) {
		if (!gj) return { type: 'FeatureCollection', features: [] };
		return {
			type: 'FeatureCollection',
			features: gj.features.map((f) => {
				const uid = String(f.properties.region_uid);
				const rec = lookup[uid] || {};
				return {
					...f,
					properties: {
						...f.properties,
						lq_value:     Number.isFinite(rec.lq)           ? rec.lq           : null,
						sales_value:  Number.isFinite(rec.sales)        ? rec.sales        : null,
						n_firms:      rec.n_firms ?? null,
						total_jobs:   Number.isFinite(rec.total_jobs)   ? rec.total_jobs   : null,
						avg_employees: Number.isFinite(rec.avg_employees) ? rec.avg_employees : null,
						abs_value: Number.isFinite(rec.absVal) ? rec.absVal : null
					}
				};
			})
		};
	}

	function fillColorExpression() {
		if (colourType === 'totals') {
			const m = Math.max(1, absClamp);
			return [
				'case',
				['==', ['feature-state', 'abs_value'], null], '#2a2a3a',
				['interpolate', ['linear'], ['feature-state', 'abs_value'], 0, SEQ_LO, m, SEQ_HI]
			];
		}
		const c = Math.max(2, lqClamp);
		return [
			'case',
			['==', ['feature-state', 'lq_value'], null], '#2a2a3a',
			['interpolate', ['linear'], ['feature-state', 'lq_value'], 1/c, UNDER, 1, MID, c, OVER]
		];
	}


	function applyData() {
		if (!mapLoaded) return;
		map.removeFeatureState({ source: SOURCE_ID, sourceLayer: SRC_LAYER });
		for (const [uid, rec] of Object.entries(recordByUid)) {
			map.setFeatureState(
				{ source: SOURCE_ID, sourceLayer: SRC_LAYER, id: uid },
				{
					lq_value:  Number.isFinite(rec.lq)     ? rec.lq     : null,
					abs_value: Number.isFinite(rec.absVal) ? rec.absVal : null,
					sales_value: Number.isFinite(rec.sales) ? rec.sales : null,
					n_firms: rec.n_firms ?? null,
					total_jobs: Number.isFinite(rec.total_jobs) ? rec.total_jobs : null,
					avg_employees: Number.isFinite(rec.avg_employees) ? rec.avg_employees : null
				}
			);
		}
		if (map.getLayer(FILL_LAYER)) map.setPaintProperty(FILL_LAYER, 'fill-color', fillColorExpression());
	}

	// re-apply whenever data or mode changes
	$: if (mapLoaded && (recordByUid || lqBasis || colourType)) applyData();


	onMount(() => {
		const style = getComputedStyle(document.documentElement);

		map = new maplibregl.Map({
			container: mapContainer,
			style: DARK_STYLE,
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 12,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: true, showZoom: true }), 'bottom-left');

		map.on('load', () => {
			// Province fill first — gives land colour + coastlines
			if (provinceGeojson) {
				map.addSource('prov', { type: 'geojson', data: provinceGeojson });
				map.addLayer({ id: 'prov-fill', type: 'fill', source: 'prov',
					paint: { 'fill-color': '#1a1a1a', 'fill-opacity': 1 } });
				map.addLayer({ id: 'prov-line', type: 'line', source: 'prov',
					paint: { 'line-color': '#333333', 'line-width': 0.8, 'line-opacity': 0.9 } });
			}

			// map.addSource(SOURCE_ID, { type: 'geojson', data: enrichGeojson(geojson, recordByUid) });
			// map.addLayer({
			// 	id: FILL_LAYER, type: 'fill', source: SOURCE_ID,
			// 	paint: { 'fill-color': fillColorExpression(), 'fill-opacity': 0.8 }
			// });
			// map.addLayer({
			// 	id: LINE_LAYER, type: 'line', source: SOURCE_ID,
			// 	paint: { 'line-color': 'rgba(255,255,255,0.15)', 'line-width': 0.4, 'line-opacity': 0.6 }
			// });

			map.addSource(SOURCE_ID, {
				type: 'vector',
				url: `pmtiles://${base}/pmtiles/csd.pmtiles`,
				promoteId: 'region_uid'
			});

			map.addLayer({
				id: FILL_LAYER,
				type: 'fill',
				source: SOURCE_ID,
				'source-layer': SRC_LAYER,
				paint: {
					'fill-color': fillColorExpression(),   // reads feature-state, see below
					'fill-opacity': 0.85
				}
			});
			map.addLayer({
				id: 'csd-line', type: 'line', source: SOURCE_ID, 'source-layer': SRC_LAYER,
				paint: { 'line-color': 'rgba(255,255,255,0.12)', 'line-width': 0.3 }
			});

			mapLoaded = true;
			applyData();        // push current data into feature-state

			map.on('mouseenter', FILL_LAYER, (event) => {
				if (!event.features?.length) return;
				map.getCanvas().style.cursor = 'pointer';
				const p = event.features[0].properties;
				const uid = String(p.region_uid);
				const name = p.region_name;
				const rec = recordByUid[uid] || {};
				const lqTxt = Number.isFinite(rec.lq) ? rec.lq.toFixed(2) + '×' : 'N/A';
				const firmsTxt = rec.n_firms ?? 'N/A';

				let rows;
				if (lqBasis === 'firms') {
					rows = `<div>LQ (firms): ${lqTxt}</div><div>Firms: ${firmsTxt}</div>`;
				} else if (lqBasis === 'jobs') {
					const jobsTxt = Number.isFinite(rec.total_jobs) ? Number(rec.total_jobs).toLocaleString() : 'N/A';
					rows = `<div>LQ (jobs): ${lqTxt}</div><div>Total jobs: ${jobsTxt}</div><div>Firms: ${firmsTxt}</div>`;
				} else {
					const salesTxt = Number.isFinite(rec.sales) ? formatSales(rec.sales) : 'Suppressed / no data';
					rows = `<div>LQ (sales): ${lqTxt}</div><div>Sales: ${salesTxt}</div><div>Firms: ${firmsTxt}</div>`;
				}

				popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false })
					.setLngLat(event.lngLat)
					.setHTML(`
						<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.6;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
							<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${name}</div>
							${rows}
						</div>`)
					.addTo(map);
			});

			map.on('mouseleave', FILL_LAYER, () => {
				map.getCanvas().style.cursor = '';
				if (popup) { popup.remove(); popup = null; }
			});

			mapLoaded = true;
			// updateChoropleth();
		});

		map.on('style.load', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
		});
		map.on('zoom', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
		});
	});

	onDestroy(() => {
		if (popup) popup.remove();
		if (map) map.remove();
		popup = null; map = null;
	});
</script>

<div class="map-wrapper">
    <div class="map" bind:this={mapContainer}></div>
	<div class="total-overlay">
		<div class="total-label">{totalLabel}</div>
		<div class="total-value">{totalDisplay}</div>
	</div>
</div>

<!-- LEGEND now OUTSIDE the wrapper, in normal flow -->
<div class="legend-bar">
	<div class="legend-inner">
   	{#if colourType === 'totals'}
		<div class="legend-title">Total {lqBasis}</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {SEQ_LO} 0%, {SEQ_HI} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">{lqBasis === 'sales' ? formatSales(0) : '0'}</span>
				<span style="left:100%">{lqBasis === 'sales' ? formatSales(absClamp) : Math.round(absClamp).toLocaleString()}</span>
			</div>
		</div>
	{:else}
		<div class="legend-title">Location quotient ({lqBasis})</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {UNDER} 0%, {MID} 50%, {OVER} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">{(1/lqClamp).toFixed(2)}×</span>
				<span style="left:50%" class="tick-strong">1.0×</span>
				<span style="left:100%">{lqClamp.toFixed(1)}×</span>
			</div>
		</div>
		<div class="legend-note">1.0× = national average</div>
	{/if}
    <div class="legend-note"><span class="swatch-grey"></span> No data / suppressed</div>
	</div>
</div>

<style>
	:global(.maplibregl-popup-tip) {
		border-top-color: #1e2433 !important;
		border-bottom-color: #1e2433 !important;
	}
	.legend-bar {
		max-width: 1080px; width: 100%; margin: 8px auto 0; padding: 8px 12px;
		font-family: OpenSans; font-size: 12px; color: var(--brandWhite);
		display: flex;
		flex-direction: column;
		align-items: center;
	}

	.legend-title { font-family: OpenSansBold; margin-bottom: 6px; align-self: flex-start; }
	.legend-note  { align-self: flex-start; }
	.legend-title { font-family: OpenSansBold; margin-bottom: 6px; }
	.legend-inner {
		width: 680px;
		
	}
	.ramp-wrap { position: relative; width: 100%; margin: 0 auto;}
	.ramp { width: 100%; height: 12px; border-radius: 2px; }
	.ticks { position: relative; height: 18px; margin-top: 2px; }
	.ticks span {
		position: absolute; transform: translateX(-50%);
		font-size: 11px; color: var(--brandWhite); white-space: nowrap;
	}
	.ticks span:first-child { transform: none; }          /* left-align at 0 */
	.ticks span:last-child  { transform: translateX(-100%); } /* right-align at 100% */
	.ticks span.tick-strong { color: var(--brandWhite); }
	/* optional: a vertical notch above the 1.0 tick */
	.ticks span.tick-strong::before {
		content: ''; position: absolute; bottom: 16px; left: 50%;
		width: 1px; height: 12px; background: var(--brandGray90);
	}
	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid rgba(255,255,255,0.1);
	}
	.map { width: 100%; height: 100%; }

	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: #1e2433; border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		/* box-shadow: 0 2px 8px rgba(0,0,0,0.4); z-index: 1; pointer-events: none; */
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

	.swatch-grey { display: inline-block; width: 12px; height: 12px; background: #2a2a3a; border: 1px solid rgba(248, 248, 248, 0.5); border-radius: 2px;}

	:global(.maplibregl-popup-content) {
		border-radius: 12px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
	:global(.maplibregl-ctrl-bottom-left) { margin: 16px; }
	@media (max-width: 720px) { .map-wrapper { height: 58vh; min-height: 380px; } }
</style>
