###
'accessKeyId'     : 'AKIAJPKNNKG2ZEYDTR3A',
'secretAccessKey' : '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',
'region'          : amazon.US_EAST_1
###
AWS = Meteor.require "aws-sdk"
temp = Meteor.require "temp"
fs = Meteor.require "fs"
util = Meteor.require "util"
Fiber = Meteor.require "fibers"

AWS.config.update({'accessKeyId': 'AKIAJPKNNKG2ZEYDTR3A', 'secretAccessKey' : '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', region: "us-east-1"});
s3 = new AWS.S3()
Meteor.startup ->
  s3.listBuckets {}, (err, data)->
    if err?
      console.log "Error loading buckets: "+err
    else if data?
      console.log "Checking for 'd2idownloads' and 'd2iscripts' bucket..."
      downloadsBucketFound = false
      scriptsBucketFound = false
      for bucket, i in data.Buckets
        console.log "   --> "+bucket.Name
        downloadsBucketFound = true if bucket.Name is "d2idownloads"
        scriptsBucketFound = true if bucket.Name is "d2iscripts"
      if not downloadsBucketFound
        console.log "Downloads bucket not found, creating..."
        s3.createBucket {ACL: "public-read", Bucket: "d2idownloads"}, (err, data)->
          console.log "Error creating bucket: "+err if err?
          console.log "Bucket created: "+data if data?
      if not scriptsBucketFound
        console.log "Scripts bucket not found, creating..."
        s3.createBucket {ACL: "public-read", Bucket: "d2iscripts"}, (err, data)->
          console.log "Error creating bucket: "+err if err?
          console.log "Bucket created: "+EJSON.stringify data if data?

Meteor.methods
  startDownload: (packageIds)->
    check packageIds, [String]
    randId = Random.id()
    error = null
    scriptsDir = null
    tempFolder = null
    downloadedCount = 0
    expectedCount = 0
    fileName = null
    result = ""
    zip = new (Meteor.require "node-zip")()
    Meteor.sync (done)->
      temp.mkdir randId, (err, dirPath)->
        if err?
          error = new Meteor.Error "FileSystem Error", err
          done()
          return
        tempFolder = dirPath
        console.log "Temporary directory created: "+dirPath
        console.log " --> downloading d2iscripts requested"
        scriptsDir = dirPath+"/scripts/"
        fs.mkdirSync scriptsDir
        Fiber(->
          for id, i in packageIds
            pkg = Packages.findOne(active:true, _id: id)
            continue if !pkg?
            pkgfid = pkg.filename
            console.log "   --> getting "+pkgfid
            expectedCount++
            s3.getObject {Bucket: "d2iscripts", Key: pkgfid}, (err, data)->
              if err?
                error = new Meteor.Error 404, "Error getting script: "+pkg.name+" - ", err
                console.log " xx> failed to get, "+err
                done()
                return
              if data?
                fileName = pkg.name.replace(" ", "").replace(/[^\w\s]/gi, "")+".lua"
                #fs.writeFile scriptsDir+"/"+pkg.name.replace(" ", "").replace(/[^\w\s]/gi, "")+".lua", data.Body
                zip.file(fileName, data.Body.toString('utf-8'))
                console.log "   ✓✓✓ "+pkg.name
                downloadedCount++
                if downloadedCount is expectedCount
                  done()
        ).run()

    Meteor.sync (done)->
      console.log " --> zipping folder"
      data = zip.generate({base64:false,compression:'DEFLATE'});
      zippedLoc = tempFolder+'/'+randId+'.zip'
      fs.writeFileSync(zippedLoc, data, 'binary');
      #console.log "Location: "+tempFolder+'/'+randId+'.zip'
      console.log " --> uploading to aws"
      fs.readFile zippedLoc, (err, zdata)->
        if err?
          error = new Meteor.Error 500, "Error opening zipped file: "+err
          done();
          return
        s3.putObject {Bucket: "d2idownloads", Key: randId+'.zip', Body: zdata}, (err, data)->
          if err?
            error = new Meteor.Error 500, "Error uploading zipped file: "+err
            done()
            return
          console.log " --> getting url"
          url = s3.getSignedUrl('getObject', {Bucket: "d2idownloads", Key: randId+'.zip'})
          console.log " --> "+url
          result = url
          done()

    if error?
      throw error
    result
