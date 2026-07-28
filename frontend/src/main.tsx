import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { AuthGate } from './auth/AuthGate.tsx'
import { AuthProvider } from './auth/AuthProvider.tsx'
import { AuthorizationProvider } from './authorization/AuthorizationProvider.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthProvider>
      <AuthorizationProvider>
        <AuthGate>
          <App />
        </AuthGate>
      </AuthorizationProvider>
    </AuthProvider>
  </StrictMode>,
)
