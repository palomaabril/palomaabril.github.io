(function () {
  const map = L.map("map", {
    scrollWheelZoom: false,
    zoomControl: true
  }).setView([19.2, -89.1], 7);

  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 18,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  }).addTo(map);

  const status = document.getElementById("map-status");
  const bins = [0, 1000, 10000, 100000, 500000, 1000000];
  const colors = ["#f4e7c1", "#dcb364", "#bf7548", "#944235", "#5b2528", "#2e1620"];

  function colorFor(value) {
    if (value >= bins[5]) return colors[5];
    if (value >= bins[4]) return colors[4];
    if (value >= bins[3]) return colors[3];
    if (value >= bins[2]) return colors[2];
    if (value >= bins[1]) return colors[1];
    return colors[0];
  }

  function formatNumber(value) {
    return new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value || 0);
  }

  function styleFeature(feature) {
    const value = Number(feature.properties.deforestation_m2 || 0);
    return {
      color: "#3c2c22",
      weight: 0.65,
      opacity: 0.65,
      fillColor: colorFor(value),
      fillOpacity: 0.72
    };
  }

  function popup(feature, layer) {
    const p = feature.properties;
    layer.bindPopup(`
      <strong>Section ${p.section_join_id}</strong><br>
      State: ${p.state_name}<br>
      Municipality: ${p.municipio}<br>
      Deforestation: ${formatNumber(Number(p.deforestation_m2))} m²
    `);
  }

  fetch("assets/maps/sections_deforestation_light.geojson")
    .then((response) => {
      if (!response.ok) throw new Error("Map GeoJSON could not be loaded.");
      return response.json();
    })
    .then((data) => {
      const layer = L.geoJSON(data, {
        style: styleFeature,
        onEachFeature: popup
      }).addTo(map);

      map.fitBounds(layer.getBounds(), { padding: [18, 18] });
      const total = data.features.reduce((sum, feature) => sum + Number(feature.properties.deforestation_m2 || 0), 0);
      status.textContent = `${data.features.length} joined sections · ${formatNumber(total)} m² total deforestation`;
    })
    .catch((error) => {
      status.textContent = error.message;
    });

  const legend = L.control({ position: "bottomleft" });
  legend.onAdd = function () {
    const div = L.DomUtil.create("div", "legend");
    div.innerHTML = `
      <div class="legend-title">Deforestation m²</div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[0]}"></span><span>&lt; 1,000</span></div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[1]}"></span><span>1,000-9,999</span></div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[2]}"></span><span>10,000-99,999</span></div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[3]}"></span><span>100,000-499,999</span></div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[4]}"></span><span>500,000-999,999</span></div>
      <div class="legend-row"><span class="legend-swatch" style="background:${colors[5]}"></span><span>1,000,000+</span></div>
    `;
    return div;
  };
  legend.addTo(map);
})();
