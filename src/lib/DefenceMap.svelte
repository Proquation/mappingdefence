<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';

	export let geojson = null;
	export let recordByUid = {};
	export let formatSales = (v) => `${v}`;
	export let lqBasis = 'sales';

	let map, mapContainer, mapLoaded = false, popup;

	const SOURCE_ID = 'regions';
	const FILL_LAYER = 'region-fill';
	const LINE_LAYER = 'region-line';

	const UNDER = '#ff6b4a';
	const MID   = '#ffffff';
	const OVER  = '#4db8ff';

	$: lqClamp = (() => {
		const vals = Object.values(recordByUid).map((r) => r.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(2, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	$: totalMetric = (() => {
		const vals = Object.values(recordByUid);
		if (lqBasis === 'sales') return vals.map((r) => r.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return vals.map((r) => r.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return vals.map((r) => Number(r.n_firms) || 0).reduce((s, v) => s + v, 0);
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
						avg_employees: Number.isFinite(rec.avg_employees) ? rec.avg_employees : null
					}
				};
			})
		};
	}

	function fillColorExpression() {
		const c = Math.max(2, lqClamp);
		return [
			'case',
			['==', ['get', 'lq_value'], null], '#2a2a3a',
			['interpolate', ['linear'], ['get', 'lq_value'],
				1 / c, UNDER,
				1,     MID,
				c,     OVER
			]
		];
	}

	function updateChoropleth() {
		if (!mapLoaded || !map) return;
		const src = map.getSource(SOURCE_ID);
		if (src) src.setData(enrichGeojson(geojson, recordByUid));
		if (map.getLayer(FILL_LAYER)) {
			map.setPaintProperty(FILL_LAYER, 'fill-color', fillColorExpression());
		}
	}

	$: if (mapLoaded && (geojson || recordByUid || lqBasis)) updateChoropleth();

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: 'https://tiles.openfreemap.org/styles/dark',
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 12,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: true, showZoom: true }), 'bottom-left');

		map.on('load', () => {
			map.addSource(SOURCE_ID, { type: 'geojson', data: enrichGeojson(geojson, recordByUid) });
			map.addLayer({
				id: FILL_LAYER, type: 'fill', source: SOURCE_ID,
				paint: { 'fill-color': fillColorExpression(), 'fill-opacity': 0.8 }
			});
			map.addLayer({
				id: LINE_LAYER, type: 'line', source: SOURCE_ID,
				paint: { 'line-color': 'rgba(255,255,255,0.15)', 'line-width': 0.4, 'line-opacity': 0.6 }
			});

			map.on('click', FILL_LAYER, (event) => {
				if (!event.features?.length) return;
				const p = event.features[0].properties;
				if (popup) popup.remove();
				const salesTxt = p.sales_value == null ? 'Suppressed / no data' : formatSales(Number(p.sales_value));
				const lqTxt    = (p.lq_value == null || p.lq_value === '') ? 'N/A' : Number(p.lq_value).toFixed(2) + '×';
				const firmsTxt = p.n_firms ?? 'N/A';
				const jobsTxt  = (p.total_jobs == null || p.total_jobs === '') ? 'N/A' : Number(p.total_jobs).toLocaleString();
				const empTxt   = (p.avg_employees == null || p.avg_employees === '') ? 'N/A' : Number(p.avg_employees).toFixed(0);

				popup = new maplibregl.Popup({ closeButton: true, closeOnClick: true })
					.setLngLat(event.lngLat)
					.setHTML(`
						<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.4;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
							<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${p.region_name}</div>
							<div>LQ (${lqBasis}): ${lqTxt}</div>
							<div>Sales: ${salesTxt}</div>
							<div>Firms: ${firmsTxt}</div>
							<div>Total jobs: ${jobsTxt}</div>
							<div>Avg. employees: ${empTxt}</div>
						</div>`)
					.addTo(map);
			});

			map.on('mouseenter', FILL_LAYER, () => { map.getCanvas().style.cursor = 'pointer'; });
			map.on('mouseleave', FILL_LAYER, () => { map.getCanvas().style.cursor = ''; });

			mapLoaded = true;
			updateChoropleth();
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
	<div class="map-legend">
		<div class="legend-title">Location quotient ({lqBasis})</div>
		<div class="legend-ramp">
			<span>under</span>
			<span class="ramp"></span>
			<span>over</span>
		</div>
		<div class="lq-mid">1.0× = national average</div>
		<div class="legend-nodata"><span class="swatch-grey"></span> No data / suppressed</div>
	</div>
</div>

<style>
	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid rgba(255,255,255,0.1);
	}
	.map { width: 100%; height: 100%; }

	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); z-index: 1; pointer-events: none;
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

	.map-legend {
		position: absolute; top: 12px; right: 12px;
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans; font-size: 12px;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); color: rgba(255,255,255,0.85);
	}
	.map-legend .legend-title { font-family: OpenSansBold; color: #ffffff; margin-bottom: 4px; }
	.legend-ramp { display: flex; align-items: center; gap: 6px; }
	.legend-ramp .ramp {
		display: inline-block; width: 120px; height: 10px; border-radius: 2px;
		border: 1px solid rgba(255,255,255,0.2);
		background: linear-gradient(to right,  #ff6b4a, #ffffff ,#4db8ff);
	}
	.lq-mid { color: rgba(255,255,255,0.5); margin-top: 4px; }
	.legend-nodata { display: flex; align-items: center; gap: 6px; margin-top: 6px; color: rgba(255,255,255,0.5); }
	.swatch-grey { display: inline-block; width: 12px; height: 12px; background: #2a2a3a; border: 1px solid rgba(255,255,255,0.2); border-radius: 2px; }

	:global(.maplibregl-popup-content) {
		border-radius: 12px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
	:global(.maplibregl-ctrl-bottom-left) { margin: 16px; }
	@media (max-width: 720px) { .map-wrapper { height: 58vh; min-height: 380px; } }
</style>
