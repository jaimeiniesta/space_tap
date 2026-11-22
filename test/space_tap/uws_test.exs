defmodule SpaceTAP.UWSTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.UWS

  @fixtures Path.expand("../fixtures", __DIR__)

  # The job documents of the services are those of a small query and of one
  # with an unknown column, captured on 2026-11-16 (the README of each
  # fixtures folder). PyVO reads the same from them, except from NED's,
  # which it can't read (test/space_tap_fixtures_pyvo_test.exs).
  describe "parse/1" do
    test "reads the job of every service, in the shape each one writes it" do
      for {service, phase, result} <- [
            {"cadc", :completed,
             "https://ws-cadc.canfar.net/minoc/files/tmp:argus/result_y374m4kk4ey22u8g.xml"},
            {"eso", :completed,
             "https://archive.eso.org/tap_obs/async/1af8314d-376b-4efc-96cc-664f9089d8cb/results/result"},
            {"exoplanet_archive", :completed,
             "http://exoplanetarchive.ipac.caltech.edu/workspace//TAP/tap_dh2b14rr/result.xml"},
            {"gaia", :completed,
             "https://gea.esac.esa.int/tap-server/tap/async/feb1b6de-e1ef-11f1-87a2-bc97e148b76b-O/results/result"},
            {"gavo", :completed,
             "http://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl/results/result"},
            {"irsa", :completed,
             "https://irsa.ipac.caltech.edu/TAP/async/28432311/results/result"},
            {"koa", :completed,
             "https://koa.ipac.caltech.edu/workspace/TAP/tap_wm4kb7qh/result.xml"},
            {"mast", :completed,
             "https://mast.stsci.edu/vo-tap/api/v0.1/caom/async/caom_42ac274f-8ad4-4112-897b-80ab78bdc1c7/results/result"},
            {"ned", :completed,
             "https://ned.ipac.caltech.edu:443/tap/async/1794855677827/results/result"}
          ] do
        assert UWS.parse(fixture(service, "completed.xml")) ==
                 {:ok, %{phase: phase, error_summary: nil, result: result}},
               service
      end
    end

    test "reads the phases a job passes through before it ends" do
      assert {:ok, %{phase: :pending, result: nil}} = UWS.parse(fixture("gavo", "pending.xml"))

      assert {:ok, %{phase: :executing, result: nil}} =
               UWS.parse(fixture("gaia", "executing.xml"))

      # IRSA lists where the result will be before the job runs.
      assert {:ok, %{phase: :queued, result: "https://irsa.ipac.caltech.edu/" <> _path}} =
               UWS.parse(fixture("irsa", "queued.xml"))
    end

    test "reads the message of the error summary, trimmed" do
      assert UWS.parse(fixture("gavo", "error.xml")) ==
               {:ok,
                %{
                  phase: :error,
                  error_summary:
                    "Field query: No such field known: column 'nosuchcolumn' could not be located in table metadata",
                  result: nil
                }}

      # Gaia writes it in a CDATA section, on two lines.
      assert {:ok, %{phase: :error, error_summary: message}} =
               UWS.parse(fixture("gaia", "error.xml"))

      assert message =~ ~r/^Cannot parse query .+ !\n - Unknown column "nosuchcolumn" !$/

      # KOA writes the quotes as character references.
      assert {:ok, %{error_summary: "ORA-00904: 'NOSUCHCOLUMN': invalid identifier"}} =
               UWS.parse(fixture("koa", "error.xml"))
    end

    test "keeps a result a job in ERROR lists, as MAST does" do
      assert {:ok,
              %{
                phase: :error,
                error_summary: "400: Exception translating ADQL" <> _rest,
                result: "https://mast.stsci.edu/" <> _path
              }} =
               UWS.parse(fixture("mast", "error.xml"))
    end

    test "finds the phase whatever the namespace prefix, and with spaces around it" do
      for job <- [
            ~s(<uws:job xmlns:uws="http://www.ivoa.net/xml/UWS/v1.0"><uws:phase>EXECUTING</uws:phase></uws:job>),
            ~s(<job xmlns="http://www.ivoa.net/xml/UWS/v1.0"><phase>EXECUTING</phase></job>),
            ~s(<job><phase>\n  EXECUTING  \n</phase></job>)
          ] do
        assert UWS.parse(job) == {:ok, %{phase: :executing, error_summary: nil, result: nil}}
      end
    end

    test "reads each of the ten phases of UWS 1.1 §2.1.3" do
      for {name, phase} <- [
            {"PENDING", :pending},
            {"QUEUED", :queued},
            {"EXECUTING", :executing},
            {"ERROR", :error},
            {"ABORTED", :aborted},
            {"UNKNOWN", :unknown},
            {"HELD", :held},
            {"SUSPENDED", :suspended},
            {"ARCHIVED", :archived}
          ] do
        assert {:ok, %{phase: ^phase}} = UWS.parse("<job><phase>#{name}</phase></job>")
      end

      assert {:ok, %{phase: :completed}} =
               UWS.parse(
                 ~s(<job><phase>COMPLETED</phase><results><result id="result" href="r"/></results></job>)
               )
    end

    test "rejects a phase UWS doesn't define, which are fixed upper-case strings" do
      for name <- ["RUNNING", "completed", ""] do
        assert UWS.parse("<job><phase>#{name}</phase></job>") ==
                 {:error, "the job document has an unknown phase: #{inspect(name)}"}
      end
    end

    test "rejects a job document without a phase, or with two" do
      assert UWS.parse("<job><jobId>1</jobId></job>") ==
               {:error, "the job document has no phase"}

      assert UWS.parse("<job><phase>QUEUED</phase><phase>EXECUTING</phase></job>") ==
               {:error, "the job document has more than one phase"}
    end

    test "reads the phase of the job only, not an element of that name elsewhere" do
      job = ~s(<job><phase>QUEUED</phase><jobInfo><phase>COMPLETED</phase></jobInfo></job>)
      assert {:ok, %{phase: :queued}} = UWS.parse(job)
    end

    test "rejects a document that isn't a job, such as a job list or a VOTable" do
      for document <- [
            File.read!(Path.join([@fixtures, "gaia", "sync_get.xml"])),
            File.read!(Path.join([@fixtures, "gavo", "syntax_error.xml"])),
            "<phase>COMPLETED</phase>"
          ] do
        assert UWS.parse(document) == {:error, "expected a UWS job document"}
      end
    end

    test "finds the result named result among the others a job lists, as CADC does" do
      job = """
      <job xmlns:xlink="http://www.w3.org/1999/xlink"><phase>COMPLETED</phase><results>
        <result id="diag" xlink:href="uws:executing:1"/>
        <result id="result" xlink:href="results/result"/>
        <result id="rowcount" xlink:href="final:3"/>
      </results></job>
      """

      # A relative href is kept as written: it is resolved against the URL of
      # the job, which the document doesn't know.
      assert UWS.parse(job) ==
               {:ok, %{phase: :completed, error_summary: nil, result: "results/result"}}
    end

    test "requires the result of a COMPLETED job (TAP 1.1 §2.2)" do
      for results <- [
            "",
            "<results/>",
            ~s(<results><result id="diag" href="d"/></results>),
            ~s(<results><result id="result" href=""/></results>),
            ~s(<results><result id="result" href="  "/></results>),
            ~s(<results><result id="result"/></results>)
          ] do
        assert UWS.parse("<job><phase>COMPLETED</phase>#{results}</job>") ==
                 {:error, "the job is COMPLETED and its document lists no result"}
      end
    end

    test "rejects a job that lists two results named result" do
      job = """
      <job><phase>COMPLETED</phase><results>
        <result id="result" href="a"/><result id="result" href="b"/>
      </results></job>
      """

      assert UWS.parse(job) == {:error, "the job document has more than one result"}
    end

    test "gives no error summary for an empty message or none" do
      for summary <- [
            ~s(<errorSummary type="fatal" hasDetail="false"><message>  </message></errorSummary>),
            ~s(<errorSummary type="fatal" hasDetail="true"/>)
          ] do
        assert UWS.parse("<job><phase>ERROR</phase>#{summary}</job>") ==
                 {:ok, %{phase: :error, error_summary: nil, result: nil}}
      end
    end

    test "rejects invalid XML and entities XML doesn't predefine" do
      assert {:error, "invalid XML: " <> _reason} = UWS.parse("<job><phase>ERROR</job>")

      assert UWS.parse(
               "<job><phase>ERROR</phase><errorSummary><message>&boom;</message></errorSummary></job>"
             ) ==
               {:error, "invalid XML: &boom; is not a predefined entity"}
    end
  end

  defp fixture(service, name), do: File.read!(Path.join([@fixtures, service, "jobs", name]))
end
