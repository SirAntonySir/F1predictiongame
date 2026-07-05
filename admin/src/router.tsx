import { createBrowserRouter } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { Dashboard } from './pages/Dashboard'
import { Drivers } from './pages/Drivers'
import { Constructors } from './pages/Constructors'
import { Sessions } from './pages/Sessions'
import { SessionDetail } from './pages/SessionDetail'
import { Leagues } from './pages/Leagues'
import { LeagueDetail } from './pages/LeagueDetail'
import { Seasons } from './pages/Seasons'
import { Users } from './pages/Users'
import { Predictions } from './pages/Predictions'
import { AvatarRegions } from './pages/AvatarRegions'
import { Notifications } from './pages/Notifications'

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
      { path: 'drivers', element: <Drivers /> },
      { path: 'constructors', element: <Constructors /> },
      { path: 'avatar-regions', element: <AvatarRegions /> },
      { path: 'notifications', element: <Notifications /> }
    ]
  }
])
