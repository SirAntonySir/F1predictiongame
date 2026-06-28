import { createBrowserRouter } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { Dashboard } from './pages/Dashboard'
import { Placeholder } from './pages/Placeholder'

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'sessions', element: <Placeholder title="Sessions" /> },
      { path: 'leagues', element: <Placeholder title="Leagues" /> },
      { path: 'users', element: <Placeholder title="Users" /> },
      { path: 'predictions', element: <Placeholder title="Predictions" /> },
      { path: 'seasons', element: <Placeholder title="Seasons" /> },
      { path: 'drivers', element: <Placeholder title="Drivers" /> },
      { path: 'constructors', element: <Placeholder title="Constructors" /> }
    ]
  }
])
