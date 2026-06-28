import { createBrowserRouter } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { Dashboard } from './pages/Dashboard'
import { Placeholder } from './pages/Placeholder'
import { Sessions } from './pages/Sessions'
import { SessionDetail } from './pages/SessionDetail'
import { Leagues } from './pages/Leagues'
import { LeagueDetail } from './pages/LeagueDetail'
import { Seasons } from './pages/Seasons'
import { Users } from './pages/Users'
import { Predictions } from './pages/Predictions'

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'sessions', element: <Sessions /> },
      { path: 'sessions/:id', element: <SessionDetail /> },
      { path: 'leagues', element: <Leagues /> },
      { path: 'leagues/:id', element: <LeagueDetail /> },
      { path: 'users', element: <Users /> },
      { path: 'predictions', element: <Predictions /> },
      { path: 'seasons', element: <Seasons /> },
      { path: 'drivers', element: <Placeholder title="Drivers" /> },
      { path: 'constructors', element: <Placeholder title="Constructors" /> }
    ]
  }
])
