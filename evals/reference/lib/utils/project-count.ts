export function projectCountLabel(count: number): string {
  if (count === 0) return 'No projects'
  return count === 1 ? '1 project' : `${count} projects`
}
