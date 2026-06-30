<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';

	export let rows = [];
	export let cmaGeojson = null;
	export let provinceGeojson = null;
	export let lqBasis = 'sales';
	export let formatSales = (v) => `${v}`;

	let map, mapContainer, mapLoaded = false, popup;


	//darker 
	// const UNDER = '#DB0707';
	// const MID   = '#999999';
	// const OVER  = '#1100BF';

	const UNDER = '#ff6b4a';
	const MID   = '#CCCCCC';
	const OVER  = '#4db8ff';

	// Minimal dark style — just a dark canvas, no tiles
	// const DARK_STYLE = {
	// 	version: 8,
	// 	glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
	// 	sources: {
	// 		osm: {
	// 			type: 'vector',
	// 			tiles: ['https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt']
	// 		}
	// 	},
	// 	layers: [
	// 		{ id: 'background', type: 'background', paint: { 'background-color': '#444444' } },
	// 		{
	// 			id: 'ocean',
	// 			type: 'fill',
	// 			source: 'osm',
	// 			'source-layer': 'ocean',
	// 			paint: { 'fill-color': '#0a0a0a' }
	// 		}
	// 	]
	// };

	const DARK_STYLE = {
		version: 8,
		glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
		sources: {},
		layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#333333' } }]
	};

	const RURAL_POINTS = {
		RURAL_ON: [-84.5, 49.5],
		RURAL_QC: [-72.0, 52.0],
		RURAL_BC: [-124.5, 54.5],
		RURAL_AB: [-114.5, 55.5],
		RURAL_SK: [-106.5, 54.5],
		RURAL_MB: [-98.5, 55.0],
		RURAL_NS: [-63.0, 45.0],
		RURAL_NB: [-66.5, 46.5],
		RURAL_NL: [-60.0, 53.0],
		RURAL_PE: [-63.2, 46.3],
		RURAL_NT: [-120.0, 64.5],
		RURAL_YT: [-135.0, 63.0],
		RURAL_NU: [-94.0, 66.0]
	};

	let centroidByUid = {};

	function computeCentroids() {
		const c = {};
		if (cmaGeojson) {
			for (const f of cmaGeojson.features) {
				const uid = String(f.properties.region_uid);
				c[uid] = polygonCentroid(f.geometry);
			}
		}
		Object.assign(c, Object.fromEntries(Object.entries(RURAL_POINTS)));
		centroidByUid = c;
	}

	function polygonCentroid(geom) {
		let x = 0, y = 0, n = 0;
		const walk = (coords) => {
			if (typeof coords[0] === 'number') { x += coords[0]; y += coords[1]; n++; }
			else coords.forEach(walk);
		};
		walk(geom.coordinates);
		return n ? [x / n, y / n] : [-95, 55];
	}

	// Short CMA labels for bubbles
	function shortCmaName(name) {
		if (!name) return '';
		// Strip province suffix like " - ON" or " (CMA)"
		return name.replace(/\s*[-–]\s*[A-Z]{2}$/, '').replace(/\s*\(CMA\).*$/, '').trim();
	}

	$: lqMin = (() => {
		const vals = bubbles.map(b => b.lq).filter(Number.isFinite);
		return vals.length ? Math.min(...vals) : 0;
	})();

	$: lqMax = (() => {
		const vals = bubbles.map(b => b.lq).filter(Number.isFinite);
		return vals.length ? Math.max(...vals) : 3;
	})();


	$: midPct = (() => {
		if (lqMax === lqMin) return 50;
		return ((1 - lqMin) / (lqMax - lqMin) * 100).toFixed(1);
	})();

	$: lqField = { sales: 'lq_sales', firms: 'lq_firms', jobs: 'lq_jobs' }[lqBasis];

	$: bubbles = (() => {
		if (!mapLoaded || !rows.length) return [];
		return rows
			.filter((r) => centroidByUid[r.region_uid])
			.map((r) => {
				const firms = (r.suppressed === true || r.suppressed === 'True') ? 0 : Number(r.n_firms) || 0;
				const sales = Number.isFinite(r.total_sales_M) ? r.total_sales_M : 0;
				const jobs  = Number.isFinite(r.total_jobs) ? r.total_jobs : 0;
				const absBasis = lqBasis === 'jobs' ? jobs : lqBasis === 'firms' ? firms : sales;
				const lqVal = Number.isFinite(r[lqField]) ? r[lqField] : null;
				return {
					uid: r.region_uid,
					name: r.region_name,
					sales, firms, jobs,
					n_firms: r.n_firms,
					total_jobs: r.total_jobs,
					avg_employees: r.avg_employees,
					suppressed: r.suppressed === true || r.suppressed === 'True',
					lngLat: centroidByUid[r.region_uid],
					lq: lqVal,
					colorVal: colourType === 'totals' ? absBasis : lqVal,
					sizeVal: colourType === 'totals'
						? (lqVal ?? 0)        // colour=totals → size by LQ
						: absBasis            // colour=lq → size by total
				};
			});
	})();

	$: totalMetric = (() => {
		if (lqBasis === 'sales') return bubbles.map((b) => b.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return bubbles.map((b) => b.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return bubbles.filter((b) => !b.suppressed).map((b) => Number(b.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel   = lqBasis === 'sales' ? 'Total sales (shown)' : lqBasis === 'jobs' ? 'Total jobs (shown)' : 'Total firms (shown)';
	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric) : totalMetric.toLocaleString();

	$: maxSales = bubbles.length ? Math.max(...bubbles.map((b) => b.sizeVal), 1) : 1;
	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(1, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	$: sizeClamp = (() => {
		const vals = bubbles.map(b => b.sizeVal).filter(v => v > 0).sort((a,b)=>a-b);
		if (!vals.length) return 1;
		// clamp at 95th pct so one extreme LQ region doesn't dwarf everything
		return vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length-1];
	})();

	$: if (mapLoaded && provinceGeojson) addProvinceLayer();

	function addProvinceLayer() {
		if (!map) return;
		if (map.getSource('prov')) {
			map.getSource('prov').setData(provinceGeojson);
			return;
		}
		map.addSource('prov', { type: 'geojson', data: provinceGeojson });
		map.addLayer(
			{ id: 'prov-fill', type: 'fill', source: 'prov',
			paint: { 'fill-color': '#1a1a1a', 'fill-opacity': 1 } },
		);
		map.addLayer(
			{ id: 'prov-line', type: 'line', source: 'prov',
			paint: { 'line-color': '#333333', 'line-width': 0.8, 'line-opacity': 0.9 } },
		);
		drawBubbles(); // keep SVG on top
	}

	function radiusPx(v) {
		const t = Math.sqrt(Math.min(v, sizeClamp) / sizeClamp);
		return 3 + t * 25;
	}

	export let colourType = 'lq';
	const SEQ_LO = '#1a2a4a', SEQ_HI = '#4db8ff';

	// 95th-pct clamp of the size metric (which equals the basis absolute value)
	$: absClamp = (() => {
		const vals = bubbles.map(b => b.colorVal).filter(v => v > 0).sort((a,b)=>a-b);
		if (!vals.length) return 1;
		return vals[Math.floor(vals.length*0.95)] ?? vals[vals.length-1];
	})();

	function colorFor(b) {
		if (colourType === 'totals') {
			if (b.suppressed || !(b.colorVal > 0)) return '#3a3a4a';
			const t = Math.min(1, b.colorVal / Math.max(1, absClamp));
			return d3.interpolateRgb(SEQ_LO, SEQ_HI)(t);
		}
		return lqColor(b.colorVal);   // colorVal is the LQ here
	}


	function lqColor(lq) {
		if (lq == null) return '#3a3a4a';
		if (lq >= 1) {
			const t = Math.min(1, (lq - 1) / (lqClamp - 1));
			return d3.interpolateRgb(MID, OVER)(t);
		}
		const t = Math.min(1, (1 - lq) / (1 - 1 / lqClamp));
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	function project(lngLat) { return map.project(lngLat); }

	function fitLabel(text, r, fontSize) {
		const approxCharWidth = fontSize * 0.62;
		const maxWidth = r * 1.7;  // slightly less than diameter
		const maxChars = Math.floor(maxWidth / approxCharWidth);
		if (!text || maxChars < 2) return '';
		if (text.length <= maxChars) return text;
		return text.slice(0, maxChars - 1) + '…';
	}

	let markerLayer;

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const zoom = map.getZoom();
		const zoomScale = 1 + Math.max(0, zoom - 3.2) * 0.18;
		// Label threshold: lower zoom = only biggest bubbles labelled
		const labelMinR = zoom < 3.2 ? 30 : zoom < 4.5 ? 22 : zoom < 5.5 ? 16 : zoom < 6.5 ? 12 : 8;

		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();

		const nodes = bubbles.map((b) => {
			const p = project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) * zoomScale };
		});

		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX((d) => project(d.lngLat).x).strength(0.25))
			.force('y', d3.forceY((d) => project(d.lngLat).y).strength(0.25))
			.force('collide', d3.forceCollide((d) => d.r + 1).strength(0.9))
			.stop();
		for (let i = 0; i < 120; i++) sim.tick();

		const g = svg.append('g');
		const node = g.selectAll('g').data(nodes).join('g')
			.attr('transform', (d) => `translate(${d.x},${d.y})`)
			.style('cursor', 'pointer')
			.on('mouseenter', (event, d) => showPopup(d))
			.on('mouseleave', () => { if (popup) { popup.remove(); popup = null; } });

		node.append('circle')
			.attr('r', (d) => d.r)
			.attr('fill', (d) => colorFor(d))
			.attr('stroke', (d) => String(d.uid).startsWith('RURAL_') ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.2)')
			.attr('stroke-width', (d) => String(d.uid).startsWith('RURAL_') ? 1.5 : 0.6)
			.attr('stroke-dasharray', (d) => String(d.uid).startsWith('RURAL_') ? '3,2' : 'none')
			.attr('fill-opacity', 0.85);

		// Labels — zoom-dependent
		node.filter((d) => d.r >= labelMinR)
			.append('text')
			.attr('text-anchor', 'middle')
			.attr('dy', '0.20em')
			.style('font-family', 'OpenSansBold')
			.style('font-size', (d) => `${Math.min(11, Math.max(8, d.r * 0.35))}px`)
			.style('fill', '#ffffff')
			.style('pointer-events', 'none')
			.style('text-shadow', '0 1px 3px rgba(0,0,0,0.8)')
			.text((d) => shortCmaName(d.name));
			

		// Second line (sales) only for larger bubbles
		// node.filter((d) => d.r >= labelMinR + 6 && !d.suppressed)
		// 	.append('text')
		// 	.attr('text-anchor', 'middle')
		// 	.attr('dy', '1.1em')
		// 	.style('font-family', 'OpenSans')
		// 	.style('font-size', '9px')
		// 	.style('fill', 'rgba(255,255,255,0.75)')
		// 	.style('pointer-events', 'none')
		// 	.text((d) => formatSales(d.sales));
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const lqTxt = d.lq == null ? 'N/A' : d.lq.toFixed(2) + '×';
		
		let rows;
		if (lqBasis === 'firms') {
			rows = `
				<div>LQ (firms): ${lqTxt}</div>
				<div>Firms: ${d.n_firms ?? 'N/A'}</div>`;
		} else if (lqBasis === 'jobs') {
			const jobsTxt = d.total_jobs == null ? 'N/A' : Number(d.total_jobs).toLocaleString();
			rows = `
				<div>LQ (jobs): ${lqTxt}</div>
				<div>Total jobs: ${jobsTxt}</div>
				<div>Firms: ${d.n_firms ?? 'N/A'}</div>`;
		} else {
			const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
			rows = `
				<div>LQ (sales): ${lqTxt}</div>
				<div>Sales: ${salesTxt}</div>
				<div>Firms: ${d.n_firms ?? 'N/A'}</div>`;
		}

		const popupLngLat = map.unproject([d.x, d.y]);
		popup = new maplibregl.Popup({ closeButton: false, closeOnClick: true })
			.setLngLat(popupLngLat)
			.setHTML(`
				<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.6;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
					<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${d.name}</div>
					${rows}
				</div>`)
			.addTo(map);
	}

	$: if (mapLoaded && (bubbles || colourType)) drawBubbles();

			onMount(() => {
				map = new maplibregl.Map({
					container: mapContainer,
					style: DARK_STYLE,
					center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 10,
					attributionControl: false,
					projection: 'globe'
				});
				map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');

				map.on('load', () => {
				// if (provinceGeojson) {
				// 	map.addSource('prov', { type: 'geojson', data: provinceGeojson });
				// 	map.addLayer({ id: 'prov-fill', type: 'fill', source: 'prov',
				// 		paint: { 'fill-color': '#1a1a1a', 'fill-opacity': 1 } });
				// 	map.addLayer({ id: 'prov-line', type: 'line', source: 'prov',
				// 		paint: { 'line-color': '#333333', 'line-width': 0.8, 'line-opacity': 0.9 } });
				// }

				// SVG overlay
				const overlay = document.createElement('div');
				overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
				const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
				svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
				svg.addEventListener('mousedown', (e) => e.stopPropagation(), false);
				overlay.appendChild(svg);
				mapContainer.appendChild(overlay);
				markerLayer = svg;
				const mo = new MutationObserver(() => {
					svg.querySelectorAll('circle').forEach((c) => (c.style.pointerEvents = 'auto'));
				});
				mo.observe(svg, { childList: true, subtree: true });

				computeCentroids();
				mapLoaded = true;
				drawBubbles();

				map.on('move', drawBubbles);
			});

		map.on('style.load', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
		});
		map.on('zoom', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
			drawBubbles();
		});

	});

	onDestroy(() => { if (popup) popup.remove(); if (map) map.remove(); map = null; });
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
				<span style="left:0%">{(1/lqClamp).toFixed(2)}×</span>
				<span style="left:50%" class="tick-strong">1.0×</span>
				<span style="left:100%">{lqClamp.toFixed(1)}×</span>
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
	</div>
</div>

<style>
	:global(.maplibregl-popup-tip) {
		border-top-color: #1e2433 !important;
		border-bottom-color: #1e2433 !important;
	}	
	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: #1e2433 ; border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		/* box-shadow: 0 2px 8px rgba(0,0,0,0.4); z-index: 1; pointer-events: none; */
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

	.rural-note {
		display: flex; align-items: center; gap: 6px;
		margin-top: 6px; color: rgba(255,255,255,0.6);
	}

	/* .ramp-lq { background: linear-gradient(to right, #ff6b4a, #CCCCCC, #4db8ff); }
	.ramp-seq { background: linear-gradient(to right, #1a2a4a, #4db8ff); } */
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

	.legend {
		position: absolute; top: 12px; right: 12px;
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans; font-size: 12px;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); color: rgba(255,255,255,0.85);
	}
	.legend-title { font-family: OpenSansBold; color: #ffffff; margin-bottom: 2px; }
	.lq-ramp { display: flex; align-items: center; gap: 6px; margin-top: 6px; border-left: 1px;   }
	.lq-mid { color: rgba(255,255,255,0.5); margin-top: 2px; }

	:global(.maplibregl-popup-content) {
		border-radius: 10px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
	:global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { filter: invert(1) brightness(0.7); }
</style>
