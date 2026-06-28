import { NavLink, Outlet } from 'react-router-dom'
import { Box, Flex, Heading } from '@radix-ui/themes'

const NAV: { to: string; label: string }[] = [
  { to: '/', label: 'Dashboard' },
  { to: '/sessions', label: 'Sessions' },
  { to: '/leagues', label: 'Leagues' },
  { to: '/users', label: 'Users' },
  { to: '/predictions', label: 'Predictions' },
  { to: '/seasons', label: 'Seasons' },
  { to: '/drivers', label: 'Drivers' },
  { to: '/constructors', label: 'Constructors' }
]

export function AppShell() {
  return (
    <Flex style={{ minHeight: '100vh' }}>
      <Box
        p="4"
        style={{ width: 220, borderRight: '2px solid var(--stroke)', background: 'var(--surface-muted)' }}
      >
        <Heading size="4" className="display" mb="4" style={{ color: 'var(--accent)' }}>
          F1PG ADMIN
        </Heading>
        <Flex direction="column" gap="1" asChild>
          <nav>
            {NAV.map((n) => (
              <NavLink
                key={n.to}
                to={n.to}
                end={n.to === '/'}
                className="label"
                style={({ isActive }) => ({
                  padding: '8px 10px',
                  borderRadius: 'var(--radius-card)',
                  color: isActive ? 'var(--accent)' : 'var(--on-surface-muted)',
                  textDecoration: 'none'
                })}
              >
                {n.label}
              </NavLink>
            ))}
          </nav>
        </Flex>
      </Box>
      <Box p="5" style={{ flex: 1 }}>
        <Outlet />
      </Box>
    </Flex>
  )
}
