SELECT
    COALESCE(ext.source::text, '(none)') AS source,
    COUNT(DISTINCT b.id) AS book_count
FROM public.books b
LEFT JOIN public.book_external_ids ext ON ext.book_id = b.id
WHERE b.deleted_at IS NULL
GROUP BY ext.source
ORDER BY book_count DESC
