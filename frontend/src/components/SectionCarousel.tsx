import { useRef } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

interface SectionCarouselProps {
  title: string
  accentColor?: 'volt' | 'plasma'
  children: React.ReactNode
  className?: string
  empty?: React.ReactNode
  isEmpty?: boolean
}

export function SectionCarousel({
  title,
  accentColor = 'volt',
  children,
  className,
  empty,
  isEmpty,
}: SectionCarouselProps) {
  const scrollRef = useRef<HTMLDivElement>(null)

  function scroll(dir: 'left' | 'right') {
    const el = scrollRef.current
    if (!el) return
    el.scrollBy({ left: dir === 'left' ? -(el.clientWidth * 0.7) : el.clientWidth * 0.7, behavior: 'smooth' })
  }

  return (
    <section className={cn('py-6', className)}>
      <div className="flex items-center justify-between px-6 mb-4">
        <div className="flex items-center gap-2.5">
          <div
            className={cn(
              'w-1.5 h-5 rounded-full',
              accentColor === 'plasma'
                ? 'bg-plasma shadow-[0_0_8px_rgba(232,121,249,0.6)]'
                : 'bg-volt-2 shadow-[0_0_8px_rgba(139,92,246,0.6)]'
            )}
          />
          <h2 className="font-display font-bold text-lg text-foreground tracking-tight">
            {title}
          </h2>
        </div>
        {!isEmpty && (
          <div className="flex gap-1">
            <Button variant="ghost" size="icon-sm" onClick={() => scroll('left')} aria-label="Scroll left">
              <ChevronLeft className="w-4 h-4" />
            </Button>
            <Button variant="ghost" size="icon-sm" onClick={() => scroll('right')} aria-label="Scroll right">
              <ChevronRight className="w-4 h-4" />
            </Button>
          </div>
        )}
      </div>

      {isEmpty ? (
        <div className="px-6">
          {empty ?? <p className="text-sm text-muted-foreground py-4">Nothing here yet.</p>}
        </div>
      ) : (
        <div
          ref={scrollRef}
          className="flex gap-3 overflow-x-auto overflow-y-visible scroll-smooth px-6 pb-2 pt-2"
          style={{ scrollbarWidth: 'none' }}
        >
          {children}
        </div>
      )}
    </section>
  )
}
