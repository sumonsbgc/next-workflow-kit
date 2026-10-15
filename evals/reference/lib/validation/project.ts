import { z } from 'zod'

export const archiveProjectSchema = z.object({ id: z.string().min(1) })
