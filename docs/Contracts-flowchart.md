<!-- Layer Titles -->
<text x="525" y="30" class="title-text" font-size="20">Diamond Contract Architecture</text>

<!-- Layer 1: Users & External Systems -->
<rect x="10" y="50" width="1030" height="100" class="group-box"/>
<text x="525" y="75" class="title-text">Layer 1: Users & External Systems</text>
<g transform="translate(150, 90)">
    <rect width="150" height="50" class="box external-box"/>
    <text x="75" y="25" class="box-title">👤 User / Bot</text>
    <text x="75" y="40" class="box-desc">Initiates Transactions</text>
</g>
<g transform="translate(750, 90)">
    <rect width="150" height="50" class="box external-box"/>
    <text x="75" y="25" class="box-title">🏦 Aave / DEXs</text>
    <text x="75" y="40" class="box-desc">External Protocols</text>
</g>

<!-- Layer 2: Diamond Core & Logic Facets -->
<rect x="10" y="160" width="1030" height="260" class="group-box"/>
<text x="525" y="185" class="title-text">Layer 2: Diamond Core & Logic Facets</text>
<g transform="translate(450, 210)">
    <rect width="150" height="50" class="box diamond-box"/>
    <text x="75" y="25" class="box-title">💎 Diamond.sol</text>
    <text x="75" y="40" class="box-desc">Proxy Entry Point</text>
</g>
<g transform="translate(30, 280)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">DiamondCutFacet</text>
    <text x="80" y="40" class="box-desc">Upgrades Diamond</text>
</g>
<g transform="translate(220, 280)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">DiamondLoupeFacet</text>
    <text x="80" y="40" class="box-desc">Inspects Diamond</text>
</g>
<g transform="translate(410, 280)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">AccessControlFacet</text>
    <text x="80" y="40" class="box-desc">Manages Roles</text>
</g>
<g transform="translate(600, 280)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">TokenHelperFacet</text>
    <text x="80" y="40" class="box-desc">Manages Tokens</text>
</g>
<g transform="translate(790, 280)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">ExchangeHelperFacet</text>
    <text x="80" y="40" class="box-desc">Manages Exchanges</text>
</g>
<g transform="translate(320, 350)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">ArbitrageFacet (V1)</text>
    <text x="80" y="40" class="box-desc">Executes Arbitrage</text>
</g>
<g transform="translate(570, 350)">
    <rect width="160" height="50" class="box facet-box"/>
    <text x="80" y="25" class="box-title">ArbitrageFacetV2</text>
    <text x="80" y="40" class="box-desc">Analyzes & Executes</text>
</g>

<!-- Layer 3: Shared Logic & Storage Libraries -->
<rect x="10" y="430" width="1030" height="380" class="group-box"/>
<text x="525" y="455" class="title-text">Layer 3: Shared Logic & Storage Libraries</text>

<!-- Storage Libraries -->
<g transform="translate(30, 480)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibDiamond</text>
    <text x="90" y="40" class="box-desc">Core Diamond Storage</text>
</g>
<g transform="translate(240, 480)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibAccessControl</text>
    <text x="90" y="40" class="box-desc">Role & Owner Storage</text>
</g>
<g transform="translate(450, 480)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibTokenHelper</text>
    <text x="90" y="40" class="box-desc">Token Registry Storage</text>
</g>
<g transform="translate(660, 480)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibExchangeHelper</text>
    <text x="90" y="40" class="box-desc">Exchange Registry Storage</text>
</g>
<g transform="translate(860, 480)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibContractRegistry</text>
    <text x="90" y="40" class="box-desc">Contract Address Storage</text>
</g>
<g transform="translate(450, 550)">
    <rect width="180" height="50" class="box storage-box"/>
    <text x="90" y="25" class="box-title">LibAppStorage</text>
    <text x="90" y="40" class="box-desc">Global App Config</text>
</g>

<!-- Action Libraries -->
<g transform="translate(30, 620)">
    <rect width="200" height="50" class="box lib-box"/>
    <text x="100" y="25" class="box-title">LibExchangeActions</text>
    <text x="100" y="40" class="box-desc">Swap Execution Logic</text>
</g>
<g transform="translate(260, 620)">
    <rect width="200" height="50" class="box lib-box"/>
    <text x="100" y="25" class="box-title">LibExchangeUtils</text>
    <text x="100" y="40" class="box-desc">DEX & Pool Identification</text>
</g>
<g transform="translate(490, 620)">
    <rect width="200" height="50" class="box lib-box"/>
    <text x="100" y="25" class="box-title">LibArbitrageCalculator</text>
    <text x="100" y="40" class="box-desc">Opportunity Analysis</text>
</g>

<!-- Layer 4: External DEX & Protocol Interfaces -->
<rect x="10" y="820" width="1030" height="120" class="group-box"/>
<text x="525" y="845" class="title-text">Layer 4: External DEX & Protocol Interfaces</text>
<g transform="translate(450, 870)">
    <rect width="150" height="50" class="box external-box"/>
    <text x="75" y="25" class="box-title">🦄 DEX Pools</text>
    <text x="75" y="40" class="box-desc">Uniswap, Sushi, etc.</text>
</g>

<!-- Arrows -->
<!-- Layer 1 to 2 -->
<path d="M 225 140 C 225 180, 480 180, 480 210" stroke="#616161" stroke-width="1.5" fill="none" marker-end="url(#arrowhead)"/>
<text x="350" y="175" class="arrow-label">Calls Diamond Functions</text>
<path d="M 825 140 C 825 190, 570 190, 570 210" stroke="#616161" stroke-width="1.5" fill="none" marker-end="url(#arrowhead)"/>
<text x="700" y="175" class="arrow-label">Flash Loan Callback</text>

<!-- Layer 2: Diamond to Facets -->
<path d="M 525 260 V 280" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 270, 110 270, 110 280" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 270, 300 270, 300 280" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 270, 680 270, 680 280" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 270, 870 270, 870 280" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 330, 400 330, 400 350" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<path d="M 525 260 C 525 330, 650 330, 650 350" class="delegate-arrow" marker-end="url(#delegate-arrowhead)"/>
<text x="525" y="270" class="arrow-label" fill="#c2185b" font-weight="bold">DELEGATECALL</text>

<!-- Layer 2 to 3: Facets to Libs -->
<path d="M 110 330 V 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 300 330 V 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 490 330 V 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 680 330 V 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 870 330 V 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="500" y="445" class="arrow-label">Uses Storage Library</text>

<path d="M 400 400 C 400 500, 540 500, 540 550" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 400 400 C 400 580, 130 580, 130 620" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="265" y="500" class="arrow-label">V1 uses Actions</text>

<path d="M 650 400 C 650 500, 540 500, 540 550" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 650 400 C 650 580, 590 580, 590 620" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="620" y="500" class="arrow-label">V2 uses Calculator</text>

<path d="M 650 400 C 650 410, 400 410, 400 400" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="525" y="415" class="arrow-label">V2 orchestrates V1</text>

<path d="M 870 330 C 900 350, 950 400, 950 480" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="910" y="400" class="arrow-label">uses</text>

<!-- Layer 3: Inter-Lib Dependencies -->
<path d="M 130 670 V 700 C 130 750, 450 750, 540 530" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 130 670 V 700 C 130 750, 660 750, 750 530" class="arrow-line" marker-end="url(#arrowhead)"/>
<path d="M 130 670 V 700 C 130 750, 860 750, 950 530" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="540" y="690" class="arrow-label">LibExchangeActions uses Token, Exchange, and Contract Registries</text>

<path d="M 590 670 C 590 700, 360 700, 360 670" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="475" y="710" class="arrow-label">Calculator uses Utils</text>

<!-- Layer 3 to 4 -->
<path d="M 130 670 V 870" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="130" y="770" class="arrow-label">Executes Swaps</text>
<path d="M 360 670 V 870" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="360" y="770" class="arrow-label">Probes Pools</text>

<!-- Layer 2 to 1 (External) -->
<path d="M 400 350 C 350 250, 750 250, 825 140" class="arrow-line" marker-end="url(#arrowhead)"/>
<text x="580" y="230" class="arrow-label">Requests Flash Loan</text>