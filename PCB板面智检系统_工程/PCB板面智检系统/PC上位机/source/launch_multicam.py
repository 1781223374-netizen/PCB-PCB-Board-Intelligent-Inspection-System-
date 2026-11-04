"""Keep receive-process bootstrap separate from the Qt application imports."""
if __name__=='__main__':
    import multiprocessing
    multiprocessing.freeze_support()
    from multi_aoi_studio import main
    raise SystemExit(main())
