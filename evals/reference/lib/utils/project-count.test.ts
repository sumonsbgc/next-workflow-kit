import { describe, expect, it } from 'vitest'
import { projectCountLabel } from './project-count'

describe('projectCountLabel', () => {
  it('labels zero, one and many', () => {
    expect(projectCountLabel(0)).toBe('No projects')
    expect(projectCountLabel(1)).toBe('1 project')
    expect(projectCountLabel(3)).toBe('3 projects')
  })
})
