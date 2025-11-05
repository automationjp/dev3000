export function LoadingSkeleton({
  itemHeight = 20,
  itemSpacing = 4,
}: {
  itemHeight?: number
  itemSpacing?: number
}) {
  return (
    <div className="bg-gray-800/30 border border-gray-700 rounded-xl p-6 animate-pulse">
      <div className="h-6 bg-gray-700 rounded w-1/3 mb-4" />
      <div className={`space-y-${itemSpacing}`}>
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className={`h-${itemHeight} bg-gray-700/50 rounded`} />
        ))}
      </div>
    </div>
  )
}
