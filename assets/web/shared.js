// ============ Cookie Management ============

function setCookie(name, value, days = 7) {
  const expires = new Date(Date.now() + days * 864e5).toUTCString();
  document.cookie = `${name}=${encodeURIComponent(value)}; expires=${expires}; path=/; SameSite=Strict`;
}

function getCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) {
    return decodeURIComponent(parts.pop().split(';').shift());
  }
  return null;
}

function deleteCookie(name) {
  document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`;
}

// ============ Session Management ============

function getSession() {
  const sessionData = getCookie('sms_session');
  if (sessionData) {
    try {
      return JSON.parse(sessionData);
    } catch (e) {
      return null;
    }
  }
  return null;
}

function setSession(token, user) {
  const sessionData = JSON.stringify({ token, user });
  setCookie('sms_session', sessionData, 7); // 7 days
}

function clearSession() {
  deleteCookie('sms_session');
}

function isLoggedIn() {
  return getSession() !== null;
}

// ============ WebSocket Connection ============

let socket = null;
let authenticated = false;
let currentUser = null;
let onMessageCallback = null;
let onConnectedCallback = null;
let onAuthenticatedCallback = null;

function connectWebSocket() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${location.host}`;

  socket = new WebSocket(wsUrl);

  socket.onopen = () => {
    updateConnectionStatus(true);

    // Try to restore session from cookie
    const session = getSession();
    if (session && session.token) {
      socket.send(JSON.stringify({
        type: 'restore_session',
        token: session.token
      }));
    }

    if (onConnectedCallback) onConnectedCallback();
  };

  socket.onclose = () => {
    updateConnectionStatus(false);
    authenticated = false;
    setTimeout(connectWebSocket, 3000);
  };

  socket.onerror = () => {
    showToast('Erreur de connexion', 'error');
  };

  socket.onmessage = (event) => {
    const data = JSON.parse(event.data);
    handleMessage(data);
  };
}

function handleMessage(data) {
  switch (data.type) {
    case 'connected':
      // Just connected, waiting for auth
      break;

    case 'login_success':
    case 'session_restored':
      currentUser = data.user;
      authenticated = true;
      setSession(data.sessionToken, data.user);
      updateUserBadge();
      if (data.type === 'login_success') {
        showToast('Connexion reussie', 'success');
      }
      if (onAuthenticatedCallback) onAuthenticatedCallback();
      break;

    case 'login_error':
      showLoginError(data.message);
      break;

    case 'session_invalid':
      clearSession();
      authenticated = false;
      currentUser = null;
      showLoginPage();
      break;

    case 'logout_success':
      clearSession();
      authenticated = false;
      currentUser = null;
      showLoginPage();
      break;

    case 'auth_required':
      showToast('Authentification requise', 'error');
      showLoginPage();
      break;

    default:
      if (onMessageCallback) onMessageCallback(data);
  }
}

function sendMessage(data) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(data));
    return true;
  }
  return false;
}

// ============ UI Helpers ============

function updateConnectionStatus(connected) {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  if (statusDot) {
    statusDot.classList.toggle('connected', connected);
  }
  if (statusText) {
    statusText.textContent = connected ? 'Connecte' : 'Deconnecte';
  }
}

function updateUserBadge() {
  const userBadge = document.getElementById('userBadge');
  if (userBadge && currentUser) {
    userBadge.textContent = currentUser.username;
    if (currentUser.isAdmin) {
      userBadge.textContent += ' (Admin)';
    }
  }
}

function showLoginPage() {
  const loginPage = document.getElementById('loginPage');
  const mainApp = document.getElementById('mainApp');
  if (loginPage) loginPage.style.display = 'flex';
  if (mainApp) mainApp.classList.remove('show');
}

function showMainApp() {
  const loginPage = document.getElementById('loginPage');
  const mainApp = document.getElementById('mainApp');
  if (loginPage) loginPage.style.display = 'none';
  if (mainApp) mainApp.classList.add('show');
  updateUserBadge();
}

function showLoginError(msg) {
  const loginError = document.getElementById('loginError');
  if (loginError) {
    loginError.textContent = msg;
    loginError.classList.add('show');
  }
}

function hideLoginError() {
  const loginError = document.getElementById('loginError');
  if (loginError) {
    loginError.classList.remove('show');
  }
}

function showToast(msg, type) {
  const toast = document.getElementById('toast');
  if (toast) {
    toast.textContent = msg;
    toast.className = `toast ${type} show`;
    setTimeout(() => toast.classList.remove('show'), 3000);
  }
}

// ============ Auth Functions ============

function login(username, password) {
  hideLoginError();
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    showLoginError('Non connecte au serveur');
    return;
  }
  sendMessage({
    type: 'login',
    username: username,
    password: password
  });
}

function logout() {
  sendMessage({ type: 'logout' });
}

// ============ Utility Functions ============

function formatTime(timestamp) {
  if (!timestamp) return '';
  const date = new Date(timestamp);
  return date.toLocaleString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
    day: '2-digit',
    month: '2-digit'
  });
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// ============ Page Initialization ============

function initPage(options = {}) {
  const {
    onMessage,
    onConnected,
    onAuthenticated,
    requireAuth = true
  } = options;

  onMessageCallback = onMessage;
  onConnectedCallback = onConnected;
  onAuthenticatedCallback = () => {
    showMainApp();
    if (onAuthenticated) onAuthenticated();
  };

  // Hide both pages initially to prevent flash
  const loginPage = document.getElementById('loginPage');
  const mainApp = document.getElementById('mainApp');
  if (loginPage) loginPage.style.display = 'none';
  if (mainApp) mainApp.classList.remove('show');

  // Setup login form
  const loginForm = document.getElementById('loginForm');
  if (loginForm) {
    loginForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const username = document.getElementById('username').value.trim();
      const password = document.getElementById('password').value;
      login(username, password);
    });
  }

  // Setup logout button
  const logoutBtn = document.getElementById('logoutBtn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', logout);
  }

  // Check if already logged in
  const session = getSession();
  if (session && session.user) {
    currentUser = session.user;
    // Will be fully authenticated after WebSocket connects and validates
  } else {
    // No session, show login page immediately
    if (loginPage) loginPage.style.display = 'flex';
  }

  // Connect WebSocket
  connectWebSocket();

  // Status check interval
  setInterval(() => {
    if (socket && socket.readyState === WebSocket.OPEN && authenticated) {
      sendMessage({ type: 'get_status' });
    }
  }, 5000);
}
