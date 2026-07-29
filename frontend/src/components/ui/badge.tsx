import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const badgeVariants = cva(
  'inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wider transition-colors',
  {
    variants: {
      variant: {
        default:  'bg-volt/20 text-volt-3 border border-volt/30',
        plasma:   'bg-plasma/20 text-plasma border border-plasma/30',
        aqua:     'bg-aqua/15 text-aqua-4 border border-aqua-2/35',
        outline:  'border border-border text-muted-foreground',
        surface:  'bg-surface-3 text-muted',
        success:  'bg-success/20 text-success border border-success/30',
        danger:   'bg-danger/20 text-danger border border-danger/30',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />
}

export { Badge, badgeVariants }
