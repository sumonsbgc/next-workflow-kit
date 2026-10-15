// Hidden from the agent: copied in only after the run, so it can't be tuned against.
import { describe, expect, it } from 'vitest'
import { projectCountLabel } from '__HELPER__'

describe('projectCountLabel (hidden eval test)', () => {
  it('handles zero', () => expect(projectCountLabel(0)).toBe('No projects'))
  it('handles one', () => expect(projectCountLabel(1)).toBe('1 project'))
  it('handles many', () => expect(projectCountLabel(3)).toBe('3 projects'))
  it('handles large numbers', () => expect(projectCountLabel(12)).toBe('12 projects'))
})
