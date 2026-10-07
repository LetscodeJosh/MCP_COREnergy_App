// State Management
let appState = {
    isLiveMode: false, // Default to mock mode first for local preview ease
    isLoggedIn: false,
    engagements: [],
    institutions: [],
    salesReps: ['jptan@profinsights.biz', 'mmperalta@pims-marketing.com', 'kmtaotao@pims-marketing.com', 'abcastro@pims-marketing.com'],
    currentScreen: 'login',
    selectedEngagement: null, // null means creating new
    currentLocation: { lat: null, lng: null },
    currentImageBase64: null,
    apiBaseUrl: 'https://dev.pmii-marketing.com'
};

// Leaflet Map instance
let mapInstance = null;
let mapMarkers = [];

// Signature drawing state
let signaturePadCanvas = null;
let signaturePadCtx = null;
let isDrawingSignature = false;
let isSignatureCanvasDrawn = false;

// DOM Elements
const elements = {
    corsToggle: document.getElementById('cors-toggle'),
    modeText: document.getElementById('mode-text'),
    modeSubtext: document.getElementById('mode-subtext'),
    loginForm: document.getElementById('login-form'),
    loginUsername: document.getElementById('login-username'),
    loginPassword: document.getElementById('login-password'),
    loginBtn: document.getElementById('login-btn'),
    togglePasswordBtn: document.getElementById('toggle-password-btn'),
    eyeIcon: document.getElementById('eye-icon'),
    
    appHeader: document.getElementById('app-header'),
    headerTitle: document.getElementById('header-title'),
    headerBack: document.getElementById('header-back'),
    headerSave: document.getElementById('header-save'),
    appNav: document.getElementById('app-nav'),
    
    screenLogin: document.getElementById('screen-login'),
    screenList: document.getElementById('screen-list'),
    screenDetail: document.getElementById('screen-detail'),
    screenMap: document.getElementById('screen-map'),
    
    tabList: document.getElementById('tab-list'),
    tabMap: document.getElementById('tab-map'),
    tabAdd: document.getElementById('tab-add'),
    
    searchInput: document.getElementById('search-input'),
    filterSalesrep: document.getElementById('filter-salesrep'),
    filterStatus: document.getElementById('filter-status'),
    recordsListContainer: document.getElementById('records-list-container'),
    
    statusDot: document.getElementById('status-dot'),
    statusText: document.getElementById('status-text'),
    toast: document.getElementById('toast-message'),
    toastText: document.getElementById('toast-text'),
    
    // Form controls
    engagementForm: document.getElementById('engagement-form'),
    unsuccessfulCall: document.getElementById('unsuccessful_call'),
    reasonUnsuccessfulGroup: document.getElementById('reason-unsuccessful-group'),
    reasonForUnsuccessfulCall: document.getElementById('reason_for_unsuccessful_call'),
    company: document.getElementById('company'),
    pictureUploaderBtn: document.getElementById('picture-uploader-btn'),
    pictureInput: document.getElementById('picture-input'),
    uploaderLabel: document.getElementById('uploader-label'),
    locationFetchBtn: document.getElementById('location-fetch-btn'),
    locationDisplay: document.getElementById('location-display'),
    salesRep: document.getElementById('sales_rep'),
    contactFirstName: document.getElementById('contact'),
    contactLastName: document.getElementById('last_name'),
    positionOrRole: document.getElementById('position_or_role'),
    emailAddress: document.getElementById('email_address'),
    contactNumber: document.getElementById('contact_number'),
    dateTimeSalesAppointment: document.getElementById('date_and_time_of_sales_appointment'),
    decisionMakerNotAvailable: document.getElementById('decision_maker_or_responsible_person_not_available'),
    detailHeaderCard: document.getElementById('detail-header-card'),
    detailIdVal: document.getElementById('detail-id-val'),
    detailTitleVal: document.getElementById('detail-title-val'),
    signaturePad: document.getElementById('signature-pad'),
    clearSignatureBtn: document.getElementById('clear-signature-btn')
};

// Initialize Application
document.addEventListener('DOMContentLoaded', () => {
    initMockData();
    setupEventListeners();
    updateUIForMode();
});

// Seed data from mock_data.js
function initMockData() {
    if (typeof mockEngagements !== 'undefined' && mockEngagements.length > 0) {
        appState.engagements = [...mockEngagements];
    }
    if (typeof mockInstitutions !== 'undefined' && mockInstitutions.length > 0) {
        appState.institutions = [...mockInstitutions];
    }
    
    // Collect any unique sales reps from mock data if they exist
    appState.engagements.forEach(item => {
        if (item.sales_rep && !appState.salesReps.includes(item.sales_rep)) {
            appState.salesReps.push(item.sales_rep);
        }
    });

    populateDropdowns();
}

function populateDropdowns() {
    // Populate Sales Rep Filter and Form Dropdown
    elements.filterSalesrep.innerHTML = '<option value="">All Sales Reps</option>';
    elements.salesRep.innerHTML = '<option value="">Select Rep...</option>';
    
    appState.salesReps.forEach(rep => {
        elements.filterSalesrep.innerHTML += `<option value="${rep}">${rep}</option>`;
        elements.salesRep.innerHTML += `<option value="${rep}">${rep}</option>`;
    });

    // Populate Company/Institution selector
    elements.company.innerHTML = '<option value="">Select Company...</option>';
    appState.institutions.forEach(inst => {
        elements.company.innerHTML += `<option value="${inst.name}">${inst.name} - ${inst.institution_name}</option>`;
    });
}

function setupEventListeners() {
    // CORS Toggle Switch
    elements.corsToggle.addEventListener('change', (e) => {
        appState.isLiveMode = e.target.checked;
        updateUIForMode();
    });

    // Login Form Submission
    elements.loginForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        setLoading(elements.loginBtn, true);
        
        const username = elements.loginUsername.value;
        const password = elements.loginPassword.value;
        
        if (appState.isLiveMode) {
            try {
                const response = await erpNextLogin(username, password);
                if (response.message === 'Logged In') {
                    showToast('Successfully authenticated with ERPNext Live!', 'success');
                    appState.isLoggedIn = true;
                    appState.loggedInUser = username;
                    
                    // Fetch live data
                    await fetchLiveData();
                    
                    // Auto-filter by logged-in user if they are a sales rep
                    if (appState.salesReps.includes(username)) {
                        elements.filterSalesrep.value = username;
                    }
                    
                    navigateTo('list');
                } else {
                    showToast('Authentication failed: check credentials', 'error');
                }
            } catch (err) {
                console.error(err);
                showToast('API connection failed. Are you blocked by CORS? Falling back to Mock mode.', 'error');
                elements.corsToggle.checked = false;
                appState.isLiveMode = false;
                updateUIForMode();
                appState.isLoggedIn = true;
                appState.loggedInUser = username;
                if (appState.salesReps.includes(username)) {
                    elements.filterSalesrep.value = username;
                }
                navigateTo('list');
            } finally {
                setLoading(elements.loginBtn, false);
            }
        } else {
            // Mock Login (always succeeds for testing with provided credentials)
            setTimeout(() => {
                setLoading(elements.loginBtn, false);
                showToast('Logged in to Local Test Environment', 'success');
                appState.isLoggedIn = true;
                appState.loggedInUser = username;
                
                // Auto-filter by logged-in user if they are a sales rep
                if (appState.salesReps.includes(username)) {
                    elements.filterSalesrep.value = username;
                } else {
                    elements.filterSalesrep.value = "";
                }
                
                navigateTo('list');
            }, 1000);
        }
    });

    // Toggle Password Visibility
    if (elements.togglePasswordBtn) {
        elements.togglePasswordBtn.addEventListener('click', () => {
            const isPassword = elements.loginPassword.type === 'password';
            elements.loginPassword.type = isPassword ? 'text' : 'password';
            
            // Toggle eye icon SVG content
            if (isPassword) {
                // Eye-off icon (slashed)
                elements.eyeIcon.innerHTML = `
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88" />
                `;
            } else {
                // Eye-on icon
                elements.eyeIcon.innerHTML = `
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    <path stroke-linecap="round" stroke-linejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                `;
            }
        });
    }

    // Navigation Tabs
    elements.tabList.addEventListener('click', () => navigateTo('list'));
    elements.tabMap.addEventListener('click', () => navigateTo('map'));
    elements.tabAdd.addEventListener('click', () => {
        appState.selectedEngagement = null;
        prepareDetailForm();
        navigateTo('detail');
    });

    // Back & Save Header Controls
    elements.headerBack.addEventListener('click', () => {
        navigateTo('list');
    });

    elements.headerSave.addEventListener('click', () => {
        saveEngagement();
    });

    // Unsuccessful call visibility toggle
    elements.unsuccessfulCall.addEventListener('change', (e) => {
        if (e.target.checked) {
            elements.reasonUnsuccessfulGroup.style.display = 'flex';
        } else {
            elements.reasonUnsuccessfulGroup.style.display = 'none';
            elements.reasonForUnsuccessfulCall.value = '';
        }
    });

    // Image upload trigger
    elements.pictureUploaderBtn.addEventListener('click', () => {
        elements.pictureInput.click();
    });

    elements.pictureInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onload = function(event) {
                appState.currentImageBase64 = event.target.result;
                displayImagePreview(appState.currentImageBase64);
                showToast('Image uploaded successfully', 'success');
            };
            reader.readAsDataURL(file);
        }
    });

    // Geolocation Fetch Button
    elements.locationFetchBtn.addEventListener('click', () => {
        if (navigator.geolocation) {
            elements.locationFetchBtn.innerHTML = '<span class="spinner"></span> Locating...';
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    appState.currentLocation = {
                        lat: position.coords.latitude.toFixed(6),
                        lng: position.coords.longitude.toFixed(6)
                    };
                    updateLocationDisplay();
                    elements.locationFetchBtn.innerHTML = 'Get Current Location';
                    showToast('Location coordinates updated', 'success');
                },
                (error) => {
                    console.warn('Geolocation failed, providing mock coordinates close to site location.');
                    // Set mock coordinates close to Canossa Santa Rosa Laguna (14.3129, 121.1009)
                    const offsetLat = (Math.random() - 0.5) * 0.05;
                    const offsetLng = (Math.random() - 0.5) * 0.05;
                    appState.currentLocation = {
                        lat: (14.3129 + offsetLat).toFixed(6),
                        lng: (121.1009 + offsetLng).toFixed(6)
                    };
                    updateLocationDisplay();
                    elements.locationFetchBtn.innerHTML = 'Get Current Location';
                    showToast('GPS disabled. Seeding realistic mockup location.', 'warning');
                },
                { timeout: 6000 }
            );
        } else {
            showToast('Geolocation not supported in this browser.', 'error');
        }
    });

    // Search and Filters
    elements.searchInput.addEventListener('input', renderList);
    elements.filterSalesrep.addEventListener('change', renderList);
    elements.filterStatus.addEventListener('change', renderList);
}

// Update Mode Info in Left panel and indicator
function updateUIForMode() {
    if (appState.isLiveMode) {
        elements.modeText.innerText = 'Live ERPNext API Mode';
        elements.modeSubtext.innerText = 'Sending updates to dev.pmii-marketing.com.';
        elements.statusDot.className = 'status-dot online';
        elements.statusText.innerText = 'Connected: Live API';
    } else {
        elements.modeText.innerText = 'Mock Data Mode';
        elements.modeSubtext.innerText = 'Running offline on cached records.';
        elements.statusDot.className = 'status-dot online';
        elements.statusText.innerText = 'Running: Local Mock DB';
    }
}

// Set loading animation on button
function setLoading(button, isLoading) {
    if (isLoading) {
        button.disabled = true;
        button.querySelector('span').innerHTML = '<span class="spinner"></span> Working...';
    } else {
        button.disabled = false;
        button.querySelector('span').innerHTML = 'Login to Environment';
    }
}

// Navigates between screens
function navigateTo(screenId) {
    appState.currentScreen = screenId;
    
    // Deactivate all screens
    elements.screenLogin.classList.remove('active');
    elements.screenList.classList.remove('active');
    elements.screenDetail.classList.remove('active');
    elements.screenMap.classList.remove('active');
    
    // Deactivate tabs
    elements.tabList.classList.remove('active');
    elements.tabMap.classList.remove('active');
    elements.tabAdd.classList.remove('active');
    
    // Reset Header Buttons
    elements.headerBack.style.visibility = 'hidden';
    elements.headerSave.style.visibility = 'hidden';

    // Activate selected screen and set headers
    if (screenId === 'login') {
        elements.appHeader.style.display = 'none';
        elements.appNav.classList.remove('visible');
        elements.screenLogin.classList.add('active');
    } else {
        elements.appHeader.style.display = 'flex';
        elements.appNav.classList.add('visible');
        
        if (screenId === 'list') {
            elements.headerTitle.innerText = 'COREnergy Engagement';
            elements.tabList.classList.add('active');
            elements.screenList.classList.add('active');
            renderList();
        } else if (screenId === 'map') {
            elements.headerTitle.innerText = 'Coverage Map';
            elements.tabMap.classList.add('active');
            elements.screenMap.classList.add('active');
            setTimeout(initMap, 100); // Allow render cycle
        } else if (screenId === 'detail') {
            elements.tabAdd.classList.add('active');
            elements.headerBack.style.visibility = 'visible';
            elements.headerSave.style.visibility = 'visible';
            elements.screenDetail.classList.add('active');
            if (appState.selectedEngagement) {
                elements.headerTitle.innerText = 'Edit Call';
            } else {
                elements.headerTitle.innerText = 'New Profiling';
            }
        }
    }
}

// Render records list cards
function renderList() {
    const query = elements.searchInput.value.toLowerCase();
    const repFilter = elements.filterSalesrep.value;
    const statusFilter = elements.filterStatus.value;
    
    elements.recordsListContainer.innerHTML = '';
    
    const filtered = appState.engagements.filter(item => {
        const matchesSearch = (item.name && item.name.toLowerCase().includes(query)) ||
                              (item.company && item.company.toLowerCase().includes(query)) ||
                              (item.contact && item.contact.toLowerCase().includes(query)) ||
                              (item.last_name && item.last_name.toLowerCase().includes(query));
        
        const matchesRep = repFilter === '' || item.sales_rep === repFilter;
        
        const isUnsuccessful = item.unsuccessful_call === 1 || item.unsuccessful_call === true;
        const matchesStatus = statusFilter === '' || 
                              (statusFilter === 'unsuccessful' && isUnsuccessful) ||
                              (statusFilter === 'successful' && !isUnsuccessful);
                              
        return matchesSearch && matchesRep && matchesStatus;
    });
    
    if (filtered.length === 0) {
        elements.recordsListContainer.innerHTML = `
            <div style="text-align: center; padding: 40px 20px; color: var(--text-muted);">
                No matching records found.
            </div>
        `;
        return;
    }
    
    // Sort by modified/creation date newest first
    filtered.sort((a, b) => new Date(b.creation || b.modified || 0) - new Date(a.creation || a.modified || 0));

    filtered.forEach(item => {
        const isUnsuccessful = item.unsuccessful_call === 1 || item.unsuccessful_call === true;
        
        // Find institution details if available
        const companyObj = appState.institutions.find(inst => inst.name === item.company);
        const companyLabel = companyObj ? companyObj.institution_name : (item.company || 'Not Assigned');
        
        const card = document.createElement('div');
        card.className = `record-card ${isUnsuccessful ? 'unsuccessful' : ''}`;
        card.innerHTML = `
            <div class="card-header-row">
                <span class="card-title">${item.name}</span>
                <span class="card-badge ${isUnsuccessful ? 'badge-danger' : 'badge-success'}">
                    ${isUnsuccessful ? 'Unsuccessful' : 'Successful'}
                </span>
            </div>
            <div class="card-meta-grid">
                <div class="meta-item">
                    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/></svg>
                    <span>${companyLabel}</span>
                </div>
                <div class="meta-item">
                    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>
                    <span>${item.sales_rep || 'No Rep'}</span>
                </div>
                <div class="meta-item">
                    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                    <span>${item.latitude && item.longitude ? `${parseFloat(item.latitude).toFixed(4)}, ${parseFloat(item.longitude).toFixed(4)}` : 'No Coordinates'}</span>
                </div>
                <div class="meta-item">
                    <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
                    <span>${formatDateString(item.creation)}</span>
                </div>
            </div>
        `;
        
        card.addEventListener('click', () => {
            appState.selectedEngagement = item;
            prepareDetailForm();
            navigateTo('detail');
        });
        
        elements.recordsListContainer.appendChild(card);
    });
}

// Format ERPNext date strings nicely
function formatDateString(str) {
    if (!str) return 'Just now';
    try {
        const d = new Date(str.replace(/-/g, '/'));
        return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' });
    } catch (e) {
        return str;
    }
}

// Display selected engagement on form
function prepareDetailForm() {
    const item = appState.selectedEngagement;
    
    // Reset Form
    elements.engagementForm.reset();
    appState.currentImageBase64 = null;
    resetImagePreview();
    
    // Setup signature canvas
    initSignaturePad();
    
    if (item) {
        // Edit Mode
        elements.detailIdVal.innerText = item.name.toUpperCase();
        elements.detailTitleVal.innerText = item.name;
        
        elements.unsuccessfulCall.checked = item.unsuccessful_call === 1 || item.unsuccessful_call === true;
        if (elements.unsuccessfulCall.checked) {
            elements.reasonUnsuccessfulGroup.style.display = 'flex';
            elements.reasonForUnsuccessfulCall.value = item.reason_for_unsuccessful_call || '';
        } else {
            elements.reasonUnsuccessfulGroup.style.display = 'none';
        }
        
        elements.company.value = item.company || '';
        elements.salesRep.value = item.sales_rep || '';
        elements.contactFirstName.value = item.contact || '';
        elements.contactLastName.value = item.last_name || '';
        elements.positionOrRole.value = item.position_or_role || '';
        elements.emailAddress.value = item.email_address || '';
        elements.contactNumber.value = item.contact_number || '';
        
        // Datetime field conversion
        if (item.date_and_time_of_sales_appointment) {
            const rawDate = item.date_and_time_of_sales_appointment; // format is usually "YYYY-MM-DD HH:MM:SS"
            const isoStr = rawDate.replace(' ', 'T').substring(0, 16);
            elements.dateTimeSalesAppointment.value = isoStr;
        } else {
            elements.dateTimeSalesAppointment.value = '';
        }
        
        elements.decisionMakerNotAvailable.checked = item.decision_maker_or_responsible_person_not_available === 1 || item.decision_maker_or_responsible_person_not_available === true;
        
        // Location coordinates
        if (item.latitude && item.longitude) {
            appState.currentLocation = { lat: item.latitude, lng: item.longitude };
        } else {
            appState.currentLocation = { lat: null, lng: null };
        }
        updateLocationDisplay();
        
        // Image display
        if (item.picture) {
            // Check if full path or relative path
            const fullImgPath = item.picture.startsWith('http') ? item.picture : `${appState.apiBaseUrl}${item.picture}`;
            displayImagePreview(fullImgPath);
        }
        
        // Signature display
        if (item.signature) {
            const img = new Image();
            img.onload = function() {
                signaturePadCtx.clearRect(0, 0, signaturePadCanvas.width, signaturePadCanvas.height);
                signaturePadCtx.drawImage(img, 0, 0, signaturePadCanvas.width, signaturePadCanvas.height);
                isSignatureCanvasDrawn = true;
            };
            img.src = item.signature.startsWith('data:') || item.signature.startsWith('http') 
                ? item.signature 
                : `${appState.apiBaseUrl}${item.signature}`;
        }
    } else {
        // Create Mode
        elements.detailIdVal.innerText = 'NEW PROFILING';
        elements.detailTitleVal.innerText = 'Create Engagement';
        elements.reasonUnsuccessfulGroup.style.display = 'none';
        appState.currentLocation = { lat: null, lng: null };
        updateLocationDisplay();
    }
}

// Update coordinates coordinates box UI
function updateLocationDisplay() {
    if (appState.currentLocation.lat && appState.currentLocation.lng) {
        elements.locationDisplay.innerHTML = `
            <div>Lat: ${appState.currentLocation.lat}</div>
            <div>Lng: ${appState.currentLocation.lng}</div>
        `;
    } else {
        elements.locationDisplay.innerHTML = `
            <div>Lat: Not set</div>
            <div>Lng: Not set</div>
        `;
    }
}

// Image preview updates
function displayImagePreview(src) {
    elements.pictureUploaderBtn.classList.add('has-image');
    elements.pictureUploaderBtn.innerHTML = `
        <img class="picture-preview" src="${src}" alt="Geotagged call preview">
        <div class="picture-overlay">
            <svg style="width:16px;height:16px;" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg>
            Change Photo
        </div>
    `;
}

function resetImagePreview() {
    elements.pictureUploaderBtn.classList.remove('has-image');
    elements.pictureUploaderBtn.innerHTML = `
        <svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
        <span id="uploader-label" style="font-size: 0.9rem; color: var(--text-muted);">Attach geotagged photo</span>
    `;
}

// Saves changes (Create or Edit)
async function saveEngagement() {
    // Basic Form validation
    if (!elements.company.value) {
        showToast('Please select a Company/Institution', 'error');
        return;
    }
    if (!elements.salesRep.value) {
        showToast('Please select a Sales Rep', 'error');
        return;
    }

    const payload = {
        unsuccessful_call: elements.unsuccessfulCall.checked ? 1 : 0,
        reason_for_unsuccessful_call: elements.reasonForUnsuccessfulCall.value || '',
        company: elements.company.value,
        sales_rep: elements.salesRep.value,
        contact: elements.contactFirstName.value || '',
        last_name: elements.contactLastName.value || '',
        position_or_role: elements.positionOrRole.value || '',
        email_address: elements.emailAddress.value || '',
        contact_number: elements.contactNumber.value || '',
        date_and_time_of_sales_appointment: elements.dateTimeSalesAppointment.value ? elements.dateTimeSalesAppointment.value.replace('T', ' ') + ':00' : null,
        decision_maker_or_responsible_person_not_available: elements.decisionMakerNotAvailable.checked ? 1 : 0,
        latitude: appState.currentLocation.lat || null,
        longitude: appState.currentLocation.lng || null,
        signature: isSignatureCanvasDrawn ? signaturePadCanvas.toDataURL('image/png') : null
    };

    if (appState.currentImageBase64) {
        payload.picture_base64 = appState.currentImageBase64; // Will send Base64 to server in Live mode
    }

    elements.headerSave.disabled = true;
    elements.headerSave.innerHTML = '<span class="spinner"></span>';

    if (appState.isLiveMode) {
        try {
            let result;
            if (appState.selectedEngagement) {
                // Update
                result = await updateLiveRecord(appState.selectedEngagement.name, payload);
                showToast('Record updated successfully in ERPNext!', 'success');
            } else {
                // Create
                result = await createLiveRecord(payload);
                showToast('Record created successfully in ERPNext!', 'success');
            }
            await fetchLiveData();
            navigateTo('list');
        } catch (err) {
            console.error(err);
            showToast('Network error while saving. Offline/CORS block suspected.', 'error');
        } finally {
            elements.headerSave.disabled = false;
            elements.headerSave.innerText = 'Save';
        }
    } else {
        // Mock Save Flow
        setTimeout(() => {
            if (appState.selectedEngagement) {
                // Update local array item
                const index = appState.engagements.findIndex(e => e.name === appState.selectedEngagement.name);
                if (index !== -1) {
                    appState.engagements[index] = {
                        ...appState.engagements[index],
                        ...payload,
                        modified: new Date().toISOString()
                    };
                }
                showToast('Changes saved to Local Mock Database', 'success');
            } else {
                // Create new local item with hash name
                const randomHash = Math.random().toString(36).substring(2, 12);
                const newRecord = {
                    name: randomHash,
                    owner: appState.salesRep.value,
                    creation: new Date().toISOString(),
                    modified: new Date().toISOString(),
                    ...payload
                };
                
                // Add picture path mock if picture uploaded
                if (appState.currentImageBase64) {
                    newRecord.picture = appState.currentImageBase64;
                }
                
                appState.engagements.unshift(newRecord);
                showToast('New call created in Local Mock Database', 'success');
            }
            elements.headerSave.disabled = false;
            elements.headerSave.innerText = 'Save';
            navigateTo('list');
        }, 1000);
    }
}

// Leaflet Map Controller
function initMap() {
    const mapElement = document.getElementById('map-container');
    if (!mapElement) return;

    if (!mapInstance) {
        // Default position to Canossa School Santa Rosa, Laguna
        mapInstance = L.map('map-container').setView([14.3129, 121.1009], 12);
        
        // Standard sleek dark theme tile layer mapping
        L.tileLayer('https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
            attribution: '&copy; Google Maps',
            maxZoom: 20
        }).addTo(mapInstance);
    }

    // Clear previous markers
    mapMarkers.forEach(m => mapInstance.removeLayer(m));
    mapMarkers = [];

    // Filter valid markers and render
    let latSum = 0;
    let lngSum = 0;
    let validCount = 0;

    appState.engagements.forEach(item => {
        if (item.latitude && item.longitude) {
            const lat = parseFloat(item.latitude);
            const lng = parseFloat(item.longitude);
            
            if (!isNaN(lat) && !isNaN(lng)) {
                latSum += lat;
                lngSum += lng;
                validCount++;

                const isUnsuccessful = item.unsuccessful_call === 1 || item.unsuccessful_call === true;
                
                // Set custom color icons
                const markerIcon = L.divIcon({
                    className: 'custom-map-pin',
                    html: `<div style="background-color: ${isUnsuccessful ? 'var(--danger)' : 'var(--primary)'}; width: 14px; height: 14px; border: 2.5px solid #fff; border-radius: 50%; box-shadow: 0 0 10px rgba(0,0,0,0.5);"></div>`,
                    iconSize: [14, 14],
                    iconAnchor: [7, 7]
                });

                const companyObj = appState.institutions.find(inst => inst.name === item.company);
                const companyName = companyObj ? companyObj.institution_name : (item.company || 'Not Set');

                const popupContent = `
                    <div style="color:#000; font-family:sans-serif; min-width:140px;">
                        <h4 style="margin:0 0 6px 0; font-size:14px;">${item.name}</h4>
                        <div style="font-size:12px; margin-bottom:4px; color:#555;"><strong>Company:</strong> ${companyName}</div>
                        <div style="font-size:12px; margin-bottom:8px; color:#555;"><strong>Rep:</strong> ${item.sales_rep || 'None'}</div>
                        <button id="map-edit-btn-${item.name}" style="background:var(--primary); color:#fff; border:none; border-radius:4px; padding:4px 8px; font-size:11px; cursor:pointer; width:100%;">View Details</button>
                    </div>
                `;

                const marker = L.marker([lat, lng], { icon: markerIcon }).addTo(mapInstance)
                    .bindPopup(popupContent);

                marker.on('popupopen', () => {
                    document.getElementById(`map-edit-btn-${item.name}`).addEventListener('click', () => {
                        appState.selectedEngagement = item;
                        prepareDetailForm();
                        navigateTo('detail');
                    });
                });

                mapMarkers.push(marker);
            }
        }
    });

    // Center map around markers if coordinates available, otherwise stay on default
    if (validCount > 0) {
        mapInstance.setView([latSum / validCount, lngSum / validCount], 11);
    }
}

// Show animated Toast alerts
function showToast(text, type = 'success') {
    elements.toastText.innerText = text;
    elements.toast.className = `toast-msg show ${type}`;
    
    // Set custom icon based on type
    if (type === 'success') {
        elements.toast.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />';
    } else if (type === 'error') {
        elements.toast.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />';
    } else if (type === 'warning') {
        elements.toast.querySelector('svg').innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />';
    }

    setTimeout(() => {
        elements.toast.classList.remove('show');
    }, 3000);
}

// ==========================================
// live API communication layers
// ==========================================

async function erpNextLogin(usr, pwd) {
    const url = `${appState.apiBaseUrl}/api/method/login`;
    const response = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        body: JSON.stringify({ usr, pwd }),
        // Include credentials (cookies) in requests for CORS/Session cookies
        credentials: 'include'
    });
    return response.json();
}

async function fetchLiveData() {
    try {
        const fields = encodeURIComponent('["name","company","latitude","longitude","location_accuracy","picture","sales_rep","contact","last_name","position_or_role","email_address","contact_number","date_and_time_of_sales_appointment","decision_maker_or_responsible_person_not_available","reason_for_unsuccessful_call","unsuccessful_call","creation","modified"]');
        const fetchSuccUrl = `${appState.apiBaseUrl}/api/resource/Successful%20COREnergy%20Engagement?fields=${fields}&limit=500`;
        const fetchUnsuccUrl = `${appState.apiBaseUrl}/api/resource/Unsuccessful%20COREnergy%20Engagement?fields=${fields}&limit=500`;
        const fetchInstUrl = `${appState.apiBaseUrl}/api/resource/Institution?fields=["name","institution_name"]&limit=500`;
        
        const [succRes, unsuccRes, instRes] = await Promise.all([
            fetch(fetchSuccUrl, { credentials: 'include' }).then(r => r.ok ? r.json() : { data: [] }).catch(() => ({ data: [] })),
            fetch(fetchUnsuccUrl, { credentials: 'include' }).then(r => r.ok ? r.json() : { data: [] }).catch(() => ({ data: [] })),
            fetch(fetchInstUrl, { credentials: 'include' }).then(r => r.ok ? r.json() : { data: [] }).catch(() => ({ data: [] }))
        ]);
        
        const combined = [];
        if (succRes.data && Array.isArray(succRes.data)) {
            succRes.data.forEach(d => { d.unsuccessful_call = 0; combined.push(d); });
        }
        if (unsuccRes.data && Array.isArray(unsuccRes.data)) {
            unsuccRes.data.forEach(d => { d.unsuccessful_call = 1; combined.push(d); });
        }
        
        if (combined.length > 0) {
            combined.sort((a, b) => (b.creation || '').localeCompare(a.creation || ''));
            appState.engagements = combined;
        }
        if (instRes.data && Array.isArray(instRes.data) && instRes.data.length > 0) {
            appState.institutions = instRes.data;
        }
        
        populateDropdowns();
        renderRecordsList();
        if (appState.currentScreen === 'map') initMap();
        showToast('Live ERPNext databases synced!', 'success');
    } catch (err) {
        showToast('Failed to pull live databases. Suspended offline.', 'error');
        throw err;
    }
}

async function createLiveRecord(payload) {
    const isUnsucc = payload.unsuccessful_call === 1 || payload.unsuccessful_call === true;
    const docType = isUnsucc ? 'Unsuccessful%20COREnergy%20Engagement' : 'Successful%20COREnergy%20Engagement';
    
    // Ensure latitude and longitude are valid strings for ERPNext
    if (!payload.latitude) payload.latitude = '0.0';
    if (!payload.longitude) payload.longitude = '0.0';
    if (!isUnsucc) delete payload.reason_for_unsuccessful_call;

    const url = `${appState.apiBaseUrl}/api/resource/${docType}`;
    const response = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        body: JSON.stringify(payload),
        credentials: 'include'
    });
    if (!response.ok) {
        const errText = await response.text();
        console.error('Create call failed:', errText);
        throw new Error('Create call failed: ' + errText);
    }
    return response.json();
}

async function updateLiveRecord(name, payload) {
    const isUnsucc = payload.unsuccessful_call === 1 || payload.unsuccessful_call === true;
    const primaryDt = isUnsucc ? 'Unsuccessful%20COREnergy%20Engagement' : 'Successful%20COREnergy%20Engagement';
    const fallbackDt = isUnsucc ? 'Successful%20COREnergy%20Engagement' : 'Unsuccessful%20COREnergy%20Engagement';

    for (const dt of [primaryDt, fallbackDt, 'COREnergy%20Engage%20Copy']) {
        try {
            const url = `${appState.apiBaseUrl}/api/resource/${dt}/${encodeURIComponent(name)}`;
            const response = await fetch(url, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                },
                body: JSON.stringify(payload),
                credentials: 'include'
            });
            if (response.ok) return response.json();
        } catch (_) {}
    }
    throw new Error('Update call failed on all DocTypes');
}

// Signature Pad Canvas drawing logic
function initSignaturePad() {
    signaturePadCanvas = elements.signaturePad;
    if (!signaturePadCanvas) return;
    signaturePadCtx = signaturePadCanvas.getContext('2d');
    
    // Match dimensions to client display layout container
    signaturePadCanvas.width = signaturePadCanvas.parentElement.clientWidth || 350;
    signaturePadCanvas.height = 120;
    
    signaturePadCtx.strokeStyle = '#5856d6';
    signaturePadCtx.lineWidth = 3;
    signaturePadCtx.lineCap = 'round';
    isSignatureCanvasDrawn = false;
    
    // Clear button event listener
    elements.clearSignatureBtn.onclick = (e) => {
        e.preventDefault();
        signaturePadCtx.clearRect(0, 0, signaturePadCanvas.width, signaturePadCanvas.height);
        isSignatureCanvasDrawn = false;
    };
    
    // Drawing handlers
    const getCoordinates = (e) => {
        const rect = signaturePadCanvas.getBoundingClientRect();
        return {
            x: (e.clientX || e.touches[0].clientX) - rect.left,
            y: (e.clientY || e.touches[0].clientY) - rect.top
        };
    };
    
    const startDraw = (e) => {
        isDrawingSignature = true;
        const coords = getCoordinates(e);
        signaturePadCtx.beginPath();
        signaturePadCtx.moveTo(coords.x, coords.y);
    };
    
    const drawMove = (e) => {
        if (!isDrawingSignature) return;
        if (e.cancelable) e.preventDefault(); // prevent touch drag scroll
        const coords = getCoordinates(e);
        signaturePadCtx.lineTo(coords.x, coords.y);
        signaturePadCtx.stroke();
        isSignatureCanvasDrawn = true;
    };
    
    const endDraw = () => {
        isDrawingSignature = false;
    };
    
    // Register events
    signaturePadCanvas.onmousedown = startDraw;
    signaturePadCanvas.onmousemove = drawMove;
    signaturePadCanvas.onmouseup = endDraw;
    signaturePadCanvas.onmouseleave = endDraw;
    
    signaturePadCanvas.ontouchstart = startDraw;
    signaturePadCanvas.ontouchmove = drawMove;
    signaturePadCanvas.ontouchend = endDraw;
}
