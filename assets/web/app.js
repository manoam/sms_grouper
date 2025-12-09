// Application state
const app = {
  socket: null,
  clientId: null,
  user: null,
  authenticated: false,
  currentPage: 'send'
};

// SMS data
const smsData = {
  inbox: [],
  outbox: []
};

// Page titles
const pageTitles = {
  send: 'Envoyer un SMS',
  inbox: 'Messages recus',
  outbox: 'Messages envoyes'
};

// DOM Elements
const loginPage = document.getElementById('loginPage');
const mainApp = document.getElementById('mainApp');
const loginForm = document.getElementById('loginForm');
const loginError = document.getElementById('loginError');
const usernameInput = document.getElementById('username');
const passwordInput = document.getElementById('password');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const userBadge = document.getElementById('userBadge');
const logoutBtn = document.getElementById('logoutBtn');
const toast = document.getElementById('toast');
const pageTitle = document.getElementById('pageTitle');
const pageFrame = document.getElementById('pageFrame');

// ============ Navigation ============

// Setup navigation
document.querySelectorAll('.nav-item[data-page]').forEach(item => {
  item.addEventListener('click', (e) => {
    e.preventDefault();
    const page = item.dataset.page;
    navigateTo(page);
  });
});

function navigateTo(page) {
  app.currentPage = page;

  // Update nav active state
  document.querySelectorAll('.nav-item[data-page]').forEach(item => {
    item.classList.toggle('active', item.dataset.page === page);
  });

  // Update title
  pageTitle.textContent = pageTitles[page];

  // Load page in iframe
  pageFrame.src = page + '.html';
}

// ============ Iframe Communication ============

window.addEventListener('message', (event) => {
  const data = event.data;

  switch (data.type) {
    case 'send_sms':
      handleSendSms(data.to, data.body);
      break;

    case 'get_inbox':
      sendToFrame({ type: 'inbox_data', messages: smsData.inbox });
      break;

    case 'get_outbox':
      sendToFrame({ type: 'outbox_data', messages: smsData.outbox });
      break;
  }
});

function sendToFrame(data) {
  if (pageFrame && pageFrame.contentWindow) {
    pageFrame.contentWindow.postMessage(data, '*');
  }
}

// ============ Send SMS ============

function handleSendSms(to, body) {
  if (!app.socket || app.socket.readyState !== WebSocket.OPEN) {
    showToast('Non connecte au serveur', 'error');
    return;
  }

  if (!app.authenticated) {
    showToast('Authentification requise', 'error');
    return;
  }

  const requestId = Date.now().toString();

  // Send to server
  app.socket.send(JSON.stringify({
    type: 'send_sms',
    to: to,
    body: body,
    requestId: requestId
  }));

  // Add to local outbox
  smsData.outbox.unshift({
    id: requestId,
    requestId: requestId,
    address: to,
    body: body,
    timestamp: new Date().toISOString(),
    status: 'pending'
  });

  // Notify frame
  sendToFrame({ type: 'sms_sent_success' });

  // Navigate to outbox
  navigateTo('outbox');
}

// ============ WebSocket ============

function connect() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${location.host}`;

  app.socket = new WebSocket(wsUrl);

  app.socket.onopen = () => {
    statusDot.classList.add('connected');
    statusText.textContent = 'Connecte';
  };

  app.socket.onclose = () => {
    statusDot.classList.remove('connected');
    statusText.textContent = 'Deconnecte';
    app.authenticated = false;
    setTimeout(connect, 3000);
  };

  app.socket.onerror = () => {
    showToast('Erreur de connexion', 'error');
  };

  app.socket.onmessage = (event) => {
    const data = JSON.parse(event.data);
    handleMessage(data);
  };
}

function handleMessage(data) {
  switch (data.type) {
    case 'connected':
      app.clientId = data.clientId;
      break;

    case 'login_success':
      app.user = data.user;
      app.authenticated = true;
      showMainApp();
      showToast('Connexion reussie', 'success');
      // Request SMS history
      app.socket.send(JSON.stringify({ type: 'get_history' }));
      break;

    case 'login_error':
      showLoginError(data.message);
      break;

    case 'logout_success':
      app.user = null;
      app.authenticated = false;
      smsData.inbox = [];
      smsData.outbox = [];
      showLoginPage();
      break;

    case 'auth_required':
      showToast('Authentification requise', 'error');
      showLoginPage();
      break;

    case 'sms_history':
      loadSmsHistory(data.messages);
      break;

    case 'sms_received':
      smsData.inbox.unshift(data.sms);
      if (app.currentPage === 'inbox') {
        sendToFrame({ type: 'inbox_data', messages: smsData.inbox });
      }
      showToast(`SMS recu de ${data.sms.address}`, 'success');
      break;

    case 'sms_sent':
      updateSmsStatus(data.requestId, 'sent');
      showToast('SMS envoye avec succes', 'success');
      break;

    case 'sms_error':
      updateSmsStatus(data.requestId, 'failed');
      showToast(`Erreur: ${data.error || 'Echec envoi'}`, 'error');
      break;

    case 'status':
    case 'pong':
      break;
  }
}

function loadSmsHistory(messages) {
  smsData.inbox = [];
  smsData.outbox = [];

  messages.forEach(sms => {
    if (sms.type === 'incoming') {
      smsData.inbox.push(sms);
    } else {
      smsData.outbox.push(sms);
    }
  });

  // Send data to current frame if needed
  if (app.currentPage === 'inbox') {
    sendToFrame({ type: 'inbox_data', messages: smsData.inbox });
  } else if (app.currentPage === 'outbox') {
    sendToFrame({ type: 'outbox_data', messages: smsData.outbox });
  }
}

function updateSmsStatus(requestId, status) {
  const sms = smsData.outbox.find(s => s.requestId === requestId || s.id === requestId);
  if (sms) {
    sms.status = status;
    if (app.currentPage === 'outbox') {
      sendToFrame({ type: 'outbox_data', messages: smsData.outbox });
    }
  }
}

// ============ Authentication ============

loginForm.addEventListener('submit', (e) => {
  e.preventDefault();
  hideLoginError();

  if (!app.socket || app.socket.readyState !== WebSocket.OPEN) {
    showLoginError('Non connecte au serveur');
    return;
  }

  app.socket.send(JSON.stringify({
    type: 'login',
    username: usernameInput.value.trim(),
    password: passwordInput.value
  }));
});

logoutBtn.addEventListener('click', () => {
  if (app.socket && app.socket.readyState === WebSocket.OPEN) {
    app.socket.send(JSON.stringify({ type: 'logout' }));
  }
});

function showLoginPage() {
  loginPage.style.display = 'flex';
  mainApp.classList.remove('show');
  passwordInput.value = '';
}

function showMainApp() {
  loginPage.style.display = 'none';
  mainApp.classList.add('show');
  userBadge.textContent = app.user?.username || 'Utilisateur';
  if (app.user?.isAdmin) {
    userBadge.textContent += ' (Admin)';
  }

  // Load default page
  navigateTo('send');
}

function showLoginError(msg) {
  loginError.textContent = msg;
  loginError.classList.add('show');
}

function hideLoginError() {
  loginError.classList.remove('show');
}

// ============ Utilities ============

function showToast(msg, type) {
  toast.textContent = msg;
  toast.className = `toast ${type} show`;
  setTimeout(() => toast.classList.remove('show'), 3000);
}

// Status check
setInterval(() => {
  if (app.socket && app.socket.readyState === WebSocket.OPEN && app.authenticated) {
    app.socket.send(JSON.stringify({ type: 'get_status' }));
  }
}, 5000);

// Start
connect();
